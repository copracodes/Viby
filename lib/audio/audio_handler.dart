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

/// Asset path of the bundled demo track for the walking-skeleton pipeline.
const String _kSampleAsset = 'assets/sample.mp3';

/// Asset path of the placeholder cover art shown in the notification.
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
/// Phase note: this is the walking skeleton. It loads one bundled asset and
/// treats the queue as a single track, so skip-next / skip-previous are stubs.
class VibyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  VibyAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();

  /// Whether playback was paused *by an audio interruption* (so we know to
  /// resume when a transient interruption ends).
  bool _pausedByInterruption = false;

  // --- Streams surfaced to PlayerService (the facade throttles/maps them) ---

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  Future<void> _init() async {
    await _configureAudioSession();

    // Rebroadcast a fresh PlaybackState whenever the player's event stream or
    // its playing flag changes. Both are needed: playbackEventStream covers
    // processing-state / position / buffering; playingStream covers the
    // play <-> pause toggle that must flip the notification button.
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) =>
          developer.log('playback event error', error: e, stackTrace: st),
    );
    _player.playingStream.listen((_) => _broadcastState());

    // Publish an initial MediaItem so the notification renders immediately,
    // then enrich it with the real duration once the asset is decoded.
    final Uri? artUri = await _preparePlaceholderArt();
    MediaItem item = MediaItem(
      id: _kSampleAsset,
      title: 'Sample',
      artist: 'Viby',
      artUri: artUri,
    );
    mediaItem.add(item);
    queue.add(<MediaItem>[item]);

    try {
      final Duration? duration = await _player.setAsset(_kSampleAsset);
      if (duration != null) {
        item = item.copyWith(duration: duration);
        mediaItem.add(item);
        queue.add(<MediaItem>[item]);
      }
    } catch (e, st) {
      developer.log('failed to load $_kSampleAsset',
          error: e, stackTrace: st);
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
            _player.setVolume(0.3);
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
            _player.setVolume(1.0);
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

  // --- Transport controls (routed from notification, buttons, and UI) ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    // Single-track walking skeleton — no queue navigation yet.
    developer.log('skipToNext: single-track skeleton, ignored');
  }

  @override
  Future<void> skipToPrevious() async {
    developer.log('skipToPrevious: single-track skeleton, ignored');
  }

  /// Releases the underlying player. Called when the whole handler is torn down.
  Future<void> dispose() => _player.dispose();
}
