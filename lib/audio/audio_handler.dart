import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/tables.dart' show RepeatMode, TrackSource;
import '../data/models/track.dart';
import 'eq_service.dart' show EqEngine;
import 'fade_envelope.dart';
import 'loop_region.dart';
import 'playback_fault.dart';
import 'replay_gain.dart';
import 'sleep_timer.dart';
import 'volume_mixer.dart';

/// Asset path of the placeholder cover art shown when a track has no artwork.
const String _kPlaceholderArtAsset = 'assets/placeholder_art.png';

/// Maps just_audio's [ProcessingState] onto audio_service's
/// [AudioProcessingState]. The two enums line up one-to-one for our purposes.
const Map<ProcessingState, AudioProcessingState> _kProcessingStateMap =
    <ProcessingState, AudioProcessingState>{
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    };

/// Maps the Viby-domain [RepeatMode] onto just_audio's [LoopMode]. Auto-advance
/// at the end of the queue is delegated to just_audio via this loop mode (the
/// queue engine keeps its own index in sync from `currentIndexStream`).
const Map<RepeatMode, LoopMode> _kLoopModeMap = <RepeatMode, LoopMode>{
  RepeatMode.off: LoopMode.off,
  RepeatMode.one: LoopMode.one,
  RepeatMode.all: LoopMode.all,
};

/// Builds the audio_service [PlaybackState] that drives the system
/// notification / lock screen from a snapshot of just_audio player state.
///
/// Extracted as a pure function (no player, no I/O) so the mapping can be
/// unit-tested against fabricated inputs. The controls list swaps play/pause
/// based on [playing]; compact indices surface previous / play-pause / next.
@visibleForTesting
PlaybackState buildPlaybackState({
  required bool playing,
  required ProcessingState processingState,
  required Duration position,
  required Duration bufferedPosition,
  required double speed,
  int? queueIndex,
}) {
  return PlaybackState(
    controls: <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ],
    systemActions: const <MediaAction>{
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    },
    // Indices into `controls`: previous (0), play/pause (1), next (3).
    androidCompactActionIndices: const <int>[0, 1, 3],
    processingState: _kProcessingStateMap[processingState]!,
    playing: playing,
    updatePosition: position,
    bufferedPosition: bufferedPosition,
    speed: speed,
    queueIndex: queueIndex,
  );
}

/// The one audio_service handler for Viby.
///
/// Wraps a single just_audio [AudioPlayer] and is the bridge between the OS
/// media session (notification, lock screen, Bluetooth/media buttons) and the
/// player. UI never touches this directly — it goes through `PlayerService`.
///
/// It owns a real, mutable playlist: [loadQueue] (re)builds it, and the
/// insert/remove/move/reorder methods mutate it *in place* (gapless — the
/// playing item is never reloaded). It does NOT own queue order or shuffle —
/// that's the queue engine's job; this handler just mirrors the order it's
/// given and reports the playing index back via [currentIndexStream].
///
/// Shuffle is handled engine-side (we own the order), so just_audio's own
/// shuffle is kept OFF and its `currentIndex` maps 1:1 onto our queue index.
class VibyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  /// [eqEngine] carries the equalizer/loudness [AudioPipeline] that must be
  /// attached at player construction (see `eq_service.dart`). It's null on
  /// platforms without EQ support, in which case the player is built plain.
  VibyAudioHandler({EqEngine? eqEngine})
      : _player = AudioPlayer(audioPipeline: eqEngine?.pipeline) {
    _init();
  }

  final AudioPlayer _player;

  /// Domain mirror of the loaded playlist, kept in lockstep with the player's
  /// audio sources so [reorderQueue] can translate an order into moves and the
  /// current-index listener can resolve the playing [MediaItem].
  List<Track> _queue = <Track>[];
  List<MediaItem> _items = <MediaItem>[];

  /// Placeholder art URI (a real file) used when a track carries no artwork.
  Uri? _placeholderArtUri;

  /// Whether playback was paused *by an audio interruption* (so we know to
  /// resume when a transient interruption ends).
  bool _pausedByInterruption = false;

  /// Failures since the last track that actually played, so we can tell "skip a
  /// rotten file" from "the whole queue is unplayable, stop". Reset whenever a
  /// track reaches `ready`.
  int _consecutiveFailures = 0;

  /// Emits when a track's file is missing / undecodable (see [PlaybackFault]).
  final StreamController<PlaybackFault> _faults =
      StreamController<PlaybackFault>.broadcast();

  // --- Volume: three factors, one authority (see volume_mixer.dart) ---------

  /// ReplayGain scalar for the current track (1.0 = untouched).
  double _gain = 1;

  /// Interruption ducking (1.0 = not ducked).
  double _duck = 1;

  /// Fade envelope: resume fade-in and the sleep timer's fade-out. A pure,
  /// clock-injected state machine (see [FadeEnvelope]); [_fadeTicker] is the
  /// only thing that advances it.
  final FadeEnvelope _fade = FadeEnvelope();

  Timer? _fadeTicker;

  ReplayGainSettings _rgSettings = const ReplayGainSettings();

  // --- Sleep timer (lives here, in the audio layer, so it keeps running with
  // the UI torn down / the app backgrounded) --------------------------------

  SleepMode? _sleepMode;
  DateTime? _sleepDeadline;
  Timer? _sleepTicker;
  final StreamController<SleepTimerState> _sleep =
      StreamController<SleepTimerState>.broadcast();
  SleepTimerState _sleepState = const SleepTimerState.idle();

  /// Whether the queue has a track after the current one — needed by
  /// [SleepEndOfQueue]. Kept in sync by the queue engine via [setHasNext].
  bool _hasNext = false;

  // --- A–B repeat -----------------------------------------------------------

  /// The armed A–B loop (null when off). While set, [_loopTicker] samples the
  /// position finely and seeks back to A on reaching B.
  LoopRegion? _loopRegion;
  Timer? _loopTicker;

  // --- Streams surfaced to PlayerService (the facade throttles/maps them) ---

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<PlaybackFault> get faultStream => _faults.stream;
  Stream<double> get speedStream => _player.speedStream;
  Stream<SleepTimerState> get sleepTimerStream => _sleep.stream;
  SleepTimerState get sleepTimerState => _sleepState;

  Future<void> _init() async {
    await _configureAudioSession();
    _placeholderArtUri = await _preparePlaceholderArt();

    // Rebroadcast a fresh PlaybackState whenever the player's event stream or
    // its playing flag changes. Both are needed: playbackEventStream covers
    // processing-state / position / buffering; playingStream covers the
    // play <-> pause toggle that must flip the notification button. Errors on
    // this stream are load/decode failures — a missing or corrupt file — which
    // we route around so the queue never stalls.
    _player.playbackEventStream.listen(
      (_) {
        // A track that reaches `ready` cleared its hurdle: reset the run.
        if (_player.processingState == ProcessingState.ready) {
          _consecutiveFailures = 0;
        }
        _broadcastState();
      },
      onError: (Object e, StackTrace st) => _handlePlaybackError(e, st),
    );
    _player.playingStream.listen((_) => _broadcastState());

    // Follow auto-advance / media-session skips: when the playing item changes,
    // surface its MediaItem so the notification shows the new track + art.
    _player.currentIndexStream.listen((int? index) {
      if (index != null) {
        _publishCurrentMediaItem(index);
        // A new track carries its own ReplayGain: re-level immediately, before
        // the first sample is heard (no fade — a track start must not swell).
        _applyGainForCurrentTrack();
        // An A–B loop belongs to a single track, so a *track change* cancels it
        // — but only a real change. just_audio re-emits the current index after
        // an in-track seek (which is exactly what the loop does on every pass),
        // so clearing on any non-null emission would cancel the loop the instant
        // it first jumped back. Gate on the index actually changing.
        if (_lastIndex != null && index != _lastIndex) _clearLoopRegion();
      }
      _lastIndex = index;
      _broadcastState();
    });
  }

  /// The last playing index seen on [currentIndexStream], to distinguish a real
  /// track change from a seek-triggered re-emit of the same index.
  int? _lastIndex;

  // --- A–B repeat -----------------------------------------------------------

  /// Arms or clears the A–B loop. While armed, a fine (50ms) sampler seeks back
  /// to A on reaching B — tighter than the 200ms position stream the facade
  /// exposes, so the loop feels seamless; the timer runs **only** while a region
  /// is set, so there's no idle cost. Clearing resumes normal playback from the
  /// current position (no seek).
  void setLoopRegion(LoopRegion? region) {
    _loopTicker?.cancel();
    _loopTicker = null;
    _loopRegion = region;
    _loopStreamController.add(region);
    if (region == null) return;
    _loopTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final LoopRegion? r = _loopRegion;
      if (r == null) return;
      if (loopShouldSeekBack(
        positionMs: _player.position.inMilliseconds,
        region: r,
      )) {
        _player.seek(Duration(milliseconds: r.aMs));
      }
    });
  }

  /// Internal cancel used by track-change / skip (a skip works normally and
  /// cancels the loop). A no-op when nothing is armed.
  void _clearLoopRegion() {
    if (_loopRegion == null && _loopTicker == null) return;
    _loopTicker?.cancel();
    _loopTicker = null;
    _loopRegion = null;
    _loopStreamController.add(null);
  }

  final StreamController<LoopRegion?> _loopStreamController =
      StreamController<LoopRegion?>.broadcast();
  Stream<LoopRegion?> get loopRegionStream => _loopStreamController.stream;
  LoopRegion? get loopRegion => _loopRegion;

  // --- Volume ---------------------------------------------------------------

  /// Pushes the composed volume to the player. The ONLY caller of setVolume.
  void _applyVolume() {
    _player.setVolume(mixVolume(gain: _gain, duck: _duck, fade: _fade.value));
  }

  void _applyGainForCurrentTrack() {
    final int? index = _player.currentIndex;
    final Track? track =
        (index != null && index >= 0 && index < _queue.length)
            ? _queue[index]
            : null;
    _gain = replayGainScalar(track?.replayGain, _rgSettings);
    _applyVolume();
  }

  /// Applies new volume-normalization settings, re-levelling the playing track
  /// at once so the change is audible while you're moving the slider.
  Future<void> setReplayGainSettings(ReplayGainSettings settings) async {
    _rgSettings = settings;
    _applyGainForCurrentTrack();
  }

  /// Drives the [FadeEnvelope]'s in-flight ramp to the player, one [kFadeTick] at
  /// a time (~60fps). Idempotent: cancels any running ticker first, and does
  /// nothing (beyond a single [_applyVolume]) if the envelope isn't ramping — so
  /// a resume during a sleep fade-out simply takes over.
  void _runFadeTicker() {
    _fadeTicker?.cancel();
    _fadeTicker = null;
    _applyVolume();
    if (!_fade.ramping) return;
    _fadeTicker = Timer.periodic(kFadeTick, (Timer t) {
      _fade.advance(kFadeTick);
      _applyVolume();
      if (!_fade.ramping) {
        t.cancel();
        _fadeTicker = null;
      }
    });
  }

  // --- Sleep timer ----------------------------------------------------------

  /// Arms the sleep timer. [SleepAfter] is anchored to an absolute deadline (not
  /// a countdown we decrement), so it stays correct even if the process is
  /// starved while backgrounded.
  Future<void> armSleepTimer(SleepMode mode) async {
    _sleepMode = mode;
    _sleepDeadline =
        mode is SleepAfter ? DateTime.now().add(mode.duration) : null;
    _sleepTicker?.cancel();
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) => _tickSleep());
    _tickSleep();
  }

  /// Pushes the deadline out by [extra] (the chip's "+15 min"). On a
  /// condition-based mode there is no deadline to extend, so this re-arms as a
  /// duration timer of [extra] from now.
  Future<void> extendSleepTimer(Duration extra) async {
    if (_sleepMode == null) return;
    final DateTime? deadline = _sleepDeadline;
    if (_sleepMode is SleepAfter && deadline != null) {
      final Duration total = deadline.add(extra).difference(DateTime.now());
      await armSleepTimer(SleepAfter(total.isNegative ? extra : total));
    } else {
      await armSleepTimer(SleepAfter(extra));
    }
  }

  /// Disarms and undoes any fade the timer had started (so the music comes back
  /// up rather than staying mysteriously quiet).
  Future<void> cancelSleepTimer() async {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepMode = null;
    _sleepDeadline = null;
    _emitSleep(const SleepTimerState.idle());
    if (_fade.value < 1) {
      _fade.ramp(1, const Duration(milliseconds: 400));
      _runFadeTicker();
    }
  }

  void _tickSleep() {
    final SleepMode? mode = _sleepMode;
    if (mode == null) return;
    final Duration? remaining = sleepRemaining(
      mode: mode,
      now: DateTime.now(),
      deadline: _sleepDeadline,
      position: _player.position,
      trackDuration: _player.duration,
      hasNext: _hasNext,
    );
    _emitSleep(SleepTimerState(mode: mode, remaining: remaining));

    // Drive the fade from `remaining` rather than a one-shot ramp: it stays
    // right if the user seeks, and a paused stretch doesn't drain the envelope.
    final double level = sleepFadeLevel(remaining);
    if (!_fade.ramping && level != _fade.value) {
      _fade.snap(level);
      _applyVolume();
    }

    if (sleepShouldStop(remaining)) {
      _sleepTicker?.cancel();
      _sleepTicker = null;
      _sleepMode = null;
      _sleepDeadline = null;
      _emitSleep(const SleepTimerState.idle());
      unawaited(_sleepStop());
    }
  }

  /// Pause, then restore the envelope so the *next* play isn't silent.
  Future<void> _sleepStop() async {
    await _player.pause();
    _fadeTicker?.cancel();
    _fadeTicker = null;
    _fade.snap(1);
    _applyVolume();
  }

  void _emitSleep(SleepTimerState state) {
    if (state == _sleepState) return;
    _sleepState = state;
    _sleep.add(state);
  }

  /// The queue engine tells us whether a next track exists (for
  /// [SleepEndOfQueue]); the handler has the playlist but not the repeat-aware
  /// answer, which the engine owns.
  void setHasNext(bool hasNext) {
    _hasNext = hasNext;
  }

  // --- Speed / skip silence -------------------------------------------------

  /// Playback speed; pitch is preserved (just_audio leaves pitch at 1.0 unless
  /// setPitch is called, so 1.5x doesn't turn into a chipmunk). Also the
  /// media-session's own `setSpeed` callback, hence the override.
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  /// Android-only in just_audio; a no-op elsewhere.
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    try {
      await _player.setSkipSilenceEnabled(enabled);
    } catch (e) {
      developer.log('skip silence unsupported here', error: e);
    }
  }

  /// Copies the bundled placeholder art to a real file so the OS media session
  /// can load it (artUri must be a resolvable file/content/http URI, not an
  /// in-bundle asset path). Returns null if the copy fails — the notification
  /// still renders, just without art.
  Future<Uri?> _preparePlaceholderArt() async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final File file = File(p.join(dir.path, 'viby_placeholder_art.png'));
      if (!file.existsSync()) {
        final ByteData bytes = await rootBundle.load(_kPlaceholderArtAsset);
        await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }
      return file.uri;
    } catch (e, st) {
      developer.log('failed to prepare placeholder art',
          error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> _configureAudioSession() async {
    final AudioSession session = await AudioSession.instance;
    // Playback category with the "music" preset: AVAudioSessionCategory.playback
    // on iOS, AndroidAudioAttributes(usage: media, contentType: music) on
    // Android — the correct profile for a foreground music app.
    await session.configure(const AudioSessionConfiguration.music());

    // Interruptions: a phone call ducks/pauses us. Transient interruptions
    // (type == pause) should resume afterwards; anything we can't classify
    // (type == unknown) is treated as permanent and we stay paused.
    session.interruptionEventStream.listen((AudioInterruptionEvent event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Ducking is a *factor*, not an absolute volume: setting 0.3 here
            // would throw away the track's ReplayGain level, and restoring 1.0
            // would silently un-normalize it.
            _duck = kDuckFactor;
            _applyVolume();
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_player.playing) {
              _pausedByInterruption = true;
              pause();
            }
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _duck = 1;
            _applyVolume();
          case AudioInterruptionType.pause:
            if (_pausedByInterruption) {
              _pausedByInterruption = false;
              play();
            }
          case AudioInterruptionType.unknown:
            // Permanent interruption — do not auto-resume.
            _pausedByInterruption = false;
        }
      }
    });

    // Headphones unplugged / disconnected: pause so audio doesn't blast from
    // the phone speaker.
    session.becomingNoisyEventStream.listen((_) => pause());
  }

  void _broadcastState() {
    playbackState.add(
      buildPlaybackState(
        playing: _player.playing,
        processingState: _player.processingState,
        position: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  // --- Queue mirror helpers ------------------------------------------------

  /// Builds a just_audio [AudioSource] for [track], tagged with its [MediaItem]
  /// so audio_service can surface it. This `switch` is the seam where subsonic
  /// streaming slots in later.
  AudioSource _buildSource(Track track) {
    switch (track.source) {
      case TrackSource.local:
        final String? path = track.filePath;
        if (path == null) {
          throw StateError('local track ${track.id} has no filePath');
        }
        return AudioSource.file(path, tag: _mediaItemFor(track));
      case TrackSource.subsonic:
        // SEAM (Phase 2): build AudioSource.uri(streamUrl, headers: auth) from
        // the server config + track.remoteId here.
        throw UnimplementedError(
          'subsonic playback is not implemented yet (track ${track.id})',
        );
    }
  }

  MediaItem _mediaItemFor(Track track) {
    final String? artPath = track.artworkPath;
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artistName,
      album: track.albumName,
      duration: track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : null,
      artUri: artPath != null ? File(artPath).uri : _placeholderArtUri,
    );
  }

  /// Republishes the whole queue and the current item to audio_service.
  void _refreshQueueBroadcast() {
    queue.add(List<MediaItem>.of(_items));
    final int? index = _player.currentIndex;
    if (index != null) _publishCurrentMediaItem(index);
  }

  void _publishCurrentMediaItem(int index) {
    if (index >= 0 && index < _items.length) mediaItem.add(_items[index]);
  }

  // --- Queue operations (driven by PlayerService / the queue engine) -------

  /// Replaces the whole queue and (re)loads the player at [initialIndex],
  /// seeked to [initialPosition]. Starts playing iff [autoPlay].
  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async {
    _queue = List<Track>.of(tracks);
    _items = _queue.map(_mediaItemFor).toList();
    queue.add(List<MediaItem>.of(_items));

    if (_queue.isEmpty) {
      await _player.stop();
      mediaItem.add(null);
      return;
    }

    final int idx = initialIndex.clamp(0, _queue.length - 1);
    _publishCurrentMediaItem(idx);

    // just_audio's own shuffle stays OFF — the engine owns order.
    await _player.setShuffleModeEnabled(false);
    try {
      await _player.setAudioSources(
        _queue.map(_buildSource).toList(),
        initialIndex: idx,
        initialPosition: initialPosition,
      );
    } catch (e, st) {
      developer.log('failed to load queue', error: e, stackTrace: st);
      return;
    }
    if (autoPlay) {
      // A fresh queue starts at its level, not faded (the fade is a *resume*
      // affordance). Reset the envelope so a ramp frozen by an earlier pause
      // can't quietly attenuate the new track.
      _fadeTicker?.cancel();
      _fadeTicker = null;
      _fade.snap(1);
      _applyVolume();
      await _player.play();
    }
  }

  Future<void> insertTrack(int index, Track track) async {
    _queue.insert(index, track);
    _items.insert(index, _mediaItemFor(track));
    await _player.insertAudioSource(index, _buildSource(track));
    _refreshQueueBroadcast();
  }

  Future<void> insertTracks(int index, List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _queue.insertAll(index, tracks);
    _items.insertAll(index, tracks.map(_mediaItemFor));
    await _player.insertAudioSources(
      index,
      tracks.map(_buildSource).toList(),
    );
    _refreshQueueBroadcast();
  }

  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    _items.removeAt(index);
    await _player.removeAudioSourceAt(index);
    if (_queue.isEmpty) mediaItem.add(null);
    _refreshQueueBroadcast();
  }

  /// In-place move; [to] is the index in the list *after* removal (matches
  /// just_audio's `moveAudioSource`).
  Future<void> moveTrack(int from, int to) async {
    if (from == to) return;
    final Track t = _queue.removeAt(from);
    _queue.insert(to, t);
    final MediaItem it = _items.removeAt(from);
    _items.insert(to, it);
    await _player.moveAudioSource(from, to);
    _refreshQueueBroadcast();
  }

  /// Reorders the loaded playlist to match [newOrder] (a permutation of the
  /// current queue) via a sequence of in-place moves, so the currently-playing
  /// item is never reloaded. Selection-sort by id: O(n) move calls.
  Future<void> reorderQueue(List<Track> newOrder) async {
    for (int i = 0; i < newOrder.length && i < _queue.length; i++) {
      if (_queue[i].id == newOrder[i].id) continue;
      int from = -1;
      for (int j = i + 1; j < _queue.length; j++) {
        if (_queue[j].id == newOrder[i].id) {
          from = j;
          break;
        }
      }
      if (from == -1) continue; // not a permutation — skip defensively.
      final Track t = _queue.removeAt(from);
      _queue.insert(i, t);
      final MediaItem it = _items.removeAt(from);
      _items.insert(i, it);
      await _player.moveAudioSource(from, i);
    }
    _refreshQueueBroadcast();
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _clearLoopRegion();
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> clearQueue() async {
    _queue = <Track>[];
    _items = <MediaItem>[];
    await _player.stop();
    await _player.clearAudioSources();
    queue.add(<MediaItem>[]);
    mediaItem.add(null);
  }

  /// The queue's repeat mode, mirrored so the fault handler can decide whether
  /// to wrap to the top of the queue when the last track fails.
  RepeatMode _repeatMode = RepeatMode.off;

  /// Applies the queue's [RepeatMode] as a just_audio loop mode. Named to avoid
  /// clashing with [BaseAudioHandler.setRepeatMode] (the media-session callback,
  /// which takes an [AudioServiceRepeatMode]).
  Future<void> applyRepeatMode(RepeatMode mode) {
    _repeatMode = mode;
    return _player.setLoopMode(_kLoopModeMap[mode]!);
  }

  /// Handles a load/decode error: emits a [PlaybackFault] and routes playback
  /// around the bad track (skip / wrap / stop) per [decidePlaybackFault]. Keeps
  /// the queue moving without UI involvement, so background playback survives a
  /// rotten file. Marking the track unplayable in the DB is the state layer's
  /// job (it listens to [faultStream]).
  Future<void> _handlePlaybackError(Object error, StackTrace st) async {
    final int index = _player.currentIndex ?? 0;
    final Track? track =
        (index >= 0 && index < _queue.length) ? _queue[index] : null;
    developer.log(
      'playback error at index $index (${track?.id})',
      error: error,
      stackTrace: st,
    );
    _consecutiveFailures++;
    final FaultDecision decision = decidePlaybackFault(
      failedIndex: index,
      queueLength: _queue.length,
      consecutiveFailures: _consecutiveFailures,
      repeat: _repeatMode,
    );
    _faults.add(PlaybackFault(
      trackId: track?.id,
      title: track?.title,
      allFailed: decision.outcome == FaultOutcome.stopAllFailed,
    ));
    switch (decision.outcome) {
      case FaultOutcome.skip:
        try {
          await _player.seek(Duration.zero, index: decision.skipIndex);
          await _player.play();
        } catch (e, s) {
          developer.log('skip-after-fault failed', error: e, stackTrace: s);
        }
      case FaultOutcome.stopAllFailed:
      case FaultOutcome.stopEnd:
        await _player.pause();
    }
  }

  // --- Transport controls (routed from notification, buttons, and UI) ------

  /// Resume, ramping the volume up over [kResumeFadeIn] instead of slamming
  /// straight back to level — the "blast" on resume is the single most jarring
  /// thing a player does, especially on headphones.
  ///
  /// This is a *resume* path only: a track that starts because the queue loaded
  /// or advanced runs through `_player.play()` internally and is not faded (a
  /// track should begin at its level, not swell into it). The fade multiplies
  /// the ReplayGain scalar rather than replacing it (see `volume_mixer.dart`),
  /// so we ramp up to the track's normalized level, never past it.
  ///
  /// The ramp is armed and ticked *before* the player's `play()` — and never
  /// awaits it. just_audio's `play()` Future does not complete until the *next*
  /// pause/stop (see its docs), so scheduling the ramp after `await _player
  /// .play()` left the envelope stranded at 0 and playback silent while the
  /// position advanced. [FadeEnvelope.resume] guarantees the ramp always lands
  /// at 1.0 regardless of how play/pause interleave.
  @override
  Future<void> play() async {
    _fade.resume(kResumeFadeIn, wasPlaying: _player.playing);
    _runFadeTicker();
    unawaited(_player.play());
  }

  @override
  Future<void> pause() async {
    _fade.cancel();
    _fadeTicker?.cancel();
    _fadeTicker = null;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToQueueItem(int index) => skipToIndex(index);

  @override
  Future<void> skipToNext() {
    _clearLoopRegion();
    return _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    _clearLoopRegion();
    // Standard player behaviour: if we're more than 3s into the track, restart
    // it rather than jumping to the previous one.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  /// Releases the underlying player. Called when the whole handler is torn down.
  Future<void> dispose() async {
    _fadeTicker?.cancel();
    _sleepTicker?.cancel();
    _loopTicker?.cancel();
    await _loopStreamController.close();
    await _faults.close();
    await _player.dispose();
  }
}
