import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/queue_playback_sink.dart';
import '../data/db/tables.dart' show RepeatMode;
import '../data/models/track.dart';
import 'player_providers.dart';

part 'queue_provider.g.dart';

/// Immutable snapshot of the play queue that the UI reads.
///
/// [tracks] is the *current* order (already shuffled when [shuffleOn]);
/// [currentIndex] points into it (or -1 when empty). Shuffle order is owned
/// here, not by just_audio.
class QueueState {
  const QueueState({
    required this.tracks,
    required this.currentIndex,
    required this.shuffleOn,
    required this.repeatMode,
  });

  const QueueState.empty()
      : tracks = const <Track>[],
        currentIndex = -1,
        shuffleOn = false,
        repeatMode = RepeatMode.off;

  final List<Track> tracks;
  final int currentIndex;
  final bool shuffleOn;
  final RepeatMode repeatMode;

  bool get isEmpty => tracks.isEmpty;
  int get length => tracks.length;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < tracks.length
          ? tracks[currentIndex]
          : null;

  /// Whether [QueueController.next] would move playback somewhere. Mirrors the
  /// engine's loop logic: with repeat off it's false at the last track (and for
  /// a single-track queue); with repeat all/one there is always a next (all
  /// wraps to the first track, one restarts the current). Drives the Next
  /// button's enabled/dimmed affordance.
  bool get hasNext {
    if (isEmpty) return false;
    switch (repeatMode) {
      case RepeatMode.one:
      case RepeatMode.all:
        return true;
      case RepeatMode.off:
        return currentIndex + 1 < length;
    }
  }

  /// Whether a *previous track* exists to jump to (independent of the 3s
  /// restart rule, which the UI layers on top). False at the first track with
  /// repeat off; always true under repeat all/one.
  bool get hasPrevious {
    if (isEmpty) return false;
    switch (repeatMode) {
      case RepeatMode.one:
      case RepeatMode.all:
        return true;
      case RepeatMode.off:
        return currentIndex > 0;
    }
  }

  QueueState copyWith({
    List<Track>? tracks,
    int? currentIndex,
    bool? shuffleOn,
    RepeatMode? repeatMode,
  }) {
    return QueueState(
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffleOn: shuffleOn ?? this.shuffleOn,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

/// The index that becomes current when playback advances *past* [current] in a
/// queue of [length] items under [mode]. Returns null to mean "stop" (end of
/// queue reached with no repeat). Mirrors the behaviour just_audio's [LoopMode]
/// implements for real auto-advance; used here for the remove-at-end decision
/// and unit-tested directly.
int? nextIndexAfterEnd(int current, int length, RepeatMode mode) {
  if (length == 0) return null;
  switch (mode) {
    case RepeatMode.one:
      return current.clamp(0, length - 1);
    case RepeatMode.all:
      return (current + 1) % length;
    case RepeatMode.off:
      return current + 1 < length ? current + 1 : null;
  }
}

/// The result of rebuilding a persisted queue after tracks may have been
/// deleted: [tracks] in saved order with missing ids dropped, [currentIndex]
/// re-anchored to the saved current (or the nearest surviving earlier track).
class RestoredQueue {
  const RestoredQueue(this.tracks, this.currentIndex);
  final List<Track> tracks;
  final int currentIndex;
}

/// Pure restore builder: keeps [trackIds] whose id resolves in [byId], in order,
/// and clamps [savedIndex] onto the surviving list. If the saved current track
/// was deleted, anchors to the nearest surviving track at or before it.
RestoredQueue buildRestoredQueue({
  required List<String> trackIds,
  required int savedIndex,
  required Map<String, Track> byId,
}) {
  final List<Track> kept = <Track>[];
  int newIndex = 0;
  for (int i = 0; i < trackIds.length; i++) {
    final Track? track = byId[trackIds[i]];
    if (track == null) continue;
    if (i <= savedIndex) newIndex = kept.length;
    kept.add(track);
  }
  if (kept.isEmpty) return const RestoredQueue(<Track>[], -1);
  return RestoredQueue(kept, newIndex.clamp(0, kept.length - 1));
}

/// The playback sink the queue engine drives. Defaults to the app's
/// `PlayerService`; overridden with a fake in tests.
@Riverpod(keepAlive: true)
QueuePlaybackSink queueSink(Ref ref) => ref.watch(playerServiceProvider);

/// Owns queue order, current index, shuffle and repeat — the single source of
/// truth for "what plays next". It updates its own state synchronously
/// (authoritative for UI + persistence) and mirrors each change into the
/// [QueuePlaybackSink]. just_audio-driven auto-advance / media-session skips are
/// reconciled back via [QueuePlaybackSink.currentIndexStream].
@Riverpod(keepAlive: true)
class QueueController extends _$QueueController {
  // Reassigned if build() re-runs (e.g. the sink provider is invalidated), so
  // it is deliberately not `late final`.
  late QueuePlaybackSink _sink;
  final Random _random = Random();

  /// Pre-shuffle order, captured when shuffle turns on so un-shuffle can restore
  /// it. Kept roughly in sync through edits while shuffled (best-effort).
  List<Track> _originalOrder = <Track>[];

  @override
  QueueState build() {
    _sink = ref.watch(queueSinkProvider);
    final StreamSubscription<int?> sub =
        _sink.currentIndexStream.listen(_onPlayerIndex);
    ref.onDispose(sub.cancel);
    return const QueueState.empty();
  }

  /// Reconciles our current index with the player's — catches auto-advance at
  /// track end and skips triggered from the notification / lock screen.
  void _onPlayerIndex(int? index) {
    if (index == null || state.isEmpty) return;
    final int clamped = index.clamp(0, state.length - 1);
    if (clamped != state.currentIndex) {
      state = state.copyWith(currentIndex: clamped);
    }
  }

  /// Keeps [_originalOrder] mirroring the queue while NOT shuffled, so a later
  /// shuffle→un-shuffle returns to the user's latest manual order.
  void _syncOriginalIfUnshuffled(List<Track> order) {
    if (!state.shuffleOn) _originalOrder = List<Track>.of(order);
  }

  // --- Building the queue --------------------------------------------------

  /// Replaces the whole queue and loads the player at [startIndex]. When
  /// [shuffle] is set, the track at [startIndex] becomes the head and the rest
  /// is shuffled after it.
  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) {
      await clear();
      return;
    }
    final int start = startIndex.clamp(0, tracks.length - 1);
    _originalOrder = List<Track>.of(tracks);

    List<Track> order;
    int index;
    if (shuffle) {
      final Track head = tracks[start];
      final List<Track> rest = List<Track>.of(tracks)..removeAt(start);
      rest.shuffle(_random);
      order = <Track>[head, ...rest];
      index = 0;
    } else {
      order = List<Track>.of(tracks);
      index = start;
    }

    state = QueueState(
      tracks: order,
      currentIndex: index,
      shuffleOn: shuffle,
      repeatMode: state.repeatMode,
    );
    await _sink.loadQueue(order, initialIndex: index, autoPlay: autoPlay);
  }

  /// Inserts [track] right after the current one and starts playing it. On an
  /// empty queue, starts a new one-track queue.
  Future<void> playNow(Track track) async {
    if (state.isEmpty) {
      await setQueue(<Track>[track], autoPlay: true);
      return;
    }
    final int at = state.currentIndex + 1;
    final List<Track> order = List<Track>.of(state.tracks)..insert(at, track);
    if (state.shuffleOn) _originalOrder = <Track>[..._originalOrder, track];
    state = state.copyWith(tracks: order, currentIndex: at);
    _syncOriginalIfUnshuffled(order);
    await _sink.insertTrack(at, track);
    await _sink.skipToIndex(at);
    await _sink.play();
  }

  /// Queues [track] to play right after the current one (no interruption).
  Future<void> playNext(Track track) async {
    if (state.isEmpty) {
      await setQueue(<Track>[track]);
      return;
    }
    final int at = state.currentIndex + 1;
    final List<Track> order = List<Track>.of(state.tracks)..insert(at, track);
    if (state.shuffleOn) _originalOrder = <Track>[..._originalOrder, track];
    state = state.copyWith(tracks: order);
    _syncOriginalIfUnshuffled(order);
    await _sink.insertTrack(at, track);
  }

  /// Appends [tracks] to the end of the queue.
  Future<void> addToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (state.isEmpty) {
      await setQueue(tracks);
      return;
    }
    final int at = state.length;
    final List<Track> order = <Track>[...state.tracks, ...tracks];
    if (state.shuffleOn) _originalOrder = <Track>[..._originalOrder, ...tracks];
    state = state.copyWith(tracks: order);
    _syncOriginalIfUnshuffled(order);
    await _sink.insertTracks(at, tracks);
  }

  Future<void> addTrack(Track track) => addToQueue(<Track>[track]);

  // --- Mutating the queue --------------------------------------------------

  /// Removes the track at [index], handling removal before / at / after the
  /// current one, and (when the *playing* track is removed at the end) stopping
  /// or wrapping per [RepeatMode].
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.length) return;
    final Track removed = state.tracks[index];
    final int old = state.currentIndex;
    final List<Track> order = List<Track>.of(state.tracks)..removeAt(index);

    // Removing the only item leaves nothing to play: stop and tear the media
    // session down (a bare removal would leave a stale notification behind).
    if (order.isEmpty) {
      await clear();
      return;
    }

    int newIndex;
    int? forcedSkip;
    bool stop = false;
    if (index < old) {
      newIndex = old - 1;
    } else if (index > old) {
      newIndex = old;
    } else {
      // Removed the currently-playing track.
      if (index < order.length) {
        // The next track slides into this slot and keeps playing.
        newIndex = index;
      } else {
        // Removed the last track while it was playing.
        final int? next =
            nextIndexAfterEnd(order.length - 1, order.length, state.repeatMode);
        if (next == null) {
          newIndex = order.length - 1;
          stop = true;
        } else {
          newIndex = next;
          forcedSkip = next;
        }
      }
    }

    if (state.shuffleOn) _originalOrder.remove(removed);
    state = state.copyWith(tracks: order, currentIndex: newIndex);
    _syncOriginalIfUnshuffled(order);

    await _sink.removeTrackAt(index);
    if (forcedSkip != null) await _sink.skipToIndex(forcedSkip);
    if (stop) await _sink.pause();
  }

  /// Removes every occurrence of the track with [trackId] from the queue (used
  /// when a playing/queued track is hidden). Removing the playing copy advances
  /// to the next track via [removeAt]. Highest index first so earlier indices
  /// stay valid as the list shrinks.
  Future<void> removeTrackById(String trackId) async {
    final List<int> indices = <int>[
      for (int i = 0; i < state.tracks.length; i++)
        if (state.tracks[i].id == trackId) i,
    ];
    for (final int index in indices.reversed) {
      await removeAt(index);
    }
  }

  /// Moves the track at [from] to [to] (index in the list *after* removal),
  /// keeping the currently-playing track correctly tracked.
  Future<void> reorder(int from, int to) async {
    if (from < 0 || from >= state.length || from == to) return;
    final List<Track> order = List<Track>.of(state.tracks);
    final Track moved = order.removeAt(from);
    final int insertAt = to.clamp(0, order.length);
    order.insert(insertAt, moved);

    int c = state.currentIndex;
    if (from == c) {
      c = insertAt;
    } else {
      if (from < c) c -= 1;
      if (insertAt <= c) c += 1;
    }

    state = state.copyWith(tracks: order, currentIndex: c);
    _syncOriginalIfUnshuffled(order);
    await _sink.moveTrack(from, insertAt);
  }

  // --- Shuffle / repeat ----------------------------------------------------

  /// Toggles shuffle without interrupting playback. Turning on: current track
  /// becomes the head of the shuffled remainder. Turning off: original order is
  /// restored and the current track is found within it.
  Future<void> toggleShuffle() async {
    if (state.isEmpty) {
      state = state.copyWith(shuffleOn: !state.shuffleOn);
      return;
    }
    final Track current = state.tracks[state.currentIndex];
    if (!state.shuffleOn) {
      _originalOrder = List<Track>.of(state.tracks);
      final List<Track> rest = List<Track>.of(state.tracks)
        ..removeAt(state.currentIndex);
      rest.shuffle(_random);
      final List<Track> order = <Track>[current, ...rest];
      state = state.copyWith(tracks: order, currentIndex: 0, shuffleOn: true);
      await _sink.reorderQueue(order);
    } else {
      final List<Track> order = List<Track>.of(_originalOrder);
      int index = order.indexOf(current);
      if (index < 0) index = 0;
      state = state.copyWith(
        tracks: order,
        currentIndex: index,
        shuffleOn: false,
      );
      await _sink.reorderQueue(order);
    }
  }

  /// Cycles repeat: off → all → one → off.
  Future<void> cycleRepeat() async {
    final RepeatMode next = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
    await _sink.setRepeatMode(next);
  }

  // --- Transport that touches the queue ------------------------------------

  Future<void> next() => _sink.skipToNext();

  Future<void> previous() => _sink.skipToPrevious();

  Future<void> skipTo(int index) async {
    if (index < 0 || index >= state.length) return;
    state = state.copyWith(currentIndex: index);
    await _sink.skipToIndex(index);
  }

  Future<void> clear() async {
    _originalOrder = <Track>[];
    state = const QueueState.empty();
    await _sink.clearQueue();
  }

  // --- Restore -------------------------------------------------------------

  /// Repopulates the queue from a restored (already resolved + filtered) track
  /// list, seeking to [position] but NOT auto-playing (cold start).
  Future<void> restore(
    List<Track> tracks, {
    required int currentIndex,
    required bool shuffleOn,
    required RepeatMode repeatMode,
    required Duration position,
  }) async {
    if (tracks.isEmpty) {
      await clear();
      return;
    }
    final int index = currentIndex.clamp(0, tracks.length - 1);
    _originalOrder = List<Track>.of(tracks);
    state = QueueState(
      tracks: tracks,
      currentIndex: index,
      shuffleOn: shuffleOn,
      repeatMode: repeatMode,
    );
    await _sink.setRepeatMode(repeatMode);
    await _sink.loadQueue(
      tracks,
      initialIndex: index,
      initialPosition: position,
      autoPlay: false,
    );
  }
}
