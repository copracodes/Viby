import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/lyrics/lyrics.dart';
import '../data/lyrics/lyrics_repository.dart';
import '../data/lyrics/lyrics_sync.dart';
import '../data/lyrics/sources/embedded_lyrics_source.dart';
import '../data/lyrics/sources/sidecar_lyrics_source.dart';
import '../data/models/track.dart';
import '../ui/player/lyrics_follow.dart';
import 'database_providers.dart';
import 'haptics_providers.dart';
import 'player_providers.dart';
import 'queue_provider.dart';

part 'lyrics_providers.g.dart';

/// The sidecar `.lrc` source. Until the user grants a lyrics folder this is a
/// [NoopSidecarSource] (always misses → embedded lyrics win); Stage 3 overrides
/// this provider with the SAF-backed source once a tree URI is granted.
@Riverpod(keepAlive: true)
SidecarLyricsSource sidecarLyricsSource(Ref ref) => const NoopSidecarSource();

/// The app-wide lyrics repository: sidecar first, then embedded (synced →
/// unsynced), all flowing through one [Lyrics] representation.
@Riverpod(keepAlive: true)
LyricsRepository lyricsRepository(Ref ref) {
  return LyricsRepository(
    dao: ref.watch(vibyDatabaseProvider).lyricsDao,
    sources: <LyricsSourceResolver>[
      ref.watch(sidecarLyricsSourceProvider),
      EmbeddedLyricsSource(),
    ],
  );
}

/// Resolved lyrics for the current track. Rebuilds **only when the track
/// changes** (it watches the current-track id, never the position stream), so
/// the list widget is stable across playback ticks.
@riverpod
Future<Lyrics> currentLyrics(Ref ref) async {
  final Track? track =
      ref.watch(queueControllerProvider.select((QueueState q) => q.currentTrack));
  if (track == null) return const Lyrics.none();
  return ref.watch(lyricsRepositoryProvider).lyricsFor(track);
}

/// The active lyric-line index at the current position — a **narrow** provider
/// returning an `int`, so a position tick that doesn't cross a line boundary
/// produces no downstream rebuild. Returns `-1` when there are no synced lyrics
/// or before the first line's time.
@riverpod
int lyricsActiveIndex(Ref ref) {
  final Lyrics? lyrics = ref.watch(currentLyricsProvider).valueOrNull;
  if (lyrics == null || !lyrics.isSynced) return -1;
  final Duration position =
      ref.watch(positionProvider).valueOrNull ?? Duration.zero;
  return activeLineIndexFor(lyrics.lines, position.inMilliseconds);
}

/// Actions on the current track's lyrics: tap-to-seek and manual refresh.
@riverpod
class LyricsController extends _$LyricsController {
  @override
  void build() {}

  /// Seeks playback to a line's start time (synced mode only; the UI gates the
  /// gesture) with the standard selection haptic.
  void seekToLine(int startMs) {
    ref.read(hapticsServiceProvider).selection();
    ref.read(playerServiceProvider).seek(Duration(milliseconds: startMs));
  }

  /// Drops the current track's cached lyrics and re-resolves from disk (the
  /// "Refresh lyrics" overflow action — e.g. after adding a `.lrc`).
  Future<void> refresh() async {
    final Track? track = ref.read(queueControllerProvider).currentTrack;
    if (track == null) return;
    await ref.read(lyricsRepositoryProvider).refresh(track);
    ref.invalidate(currentLyricsProvider);
  }
}

/// The auto-follow override state for the expanded lyrics view. Owns the 4s idle
/// timer; the transition table lives in [nextFollowState] (pure, tested).
@riverpod
class LyricsFollowController extends _$LyricsFollowController {
  Timer? _resumeTimer;

  @override
  LyricsFollowState build() {
    // Resetting to `following` on track change is driven by the UI dispatching
    // [LyricsFollowEvent.trackChanged]; cancel the timer when disposed.
    ref.onDispose(() => _resumeTimer?.cancel());
    return const LyricsFollowState.following();
  }

  /// Dispatches [event] through the pure reducer and (re)arms/cancels the idle
  /// timer as [shouldArmResumeTimer] dictates.
  void dispatch(LyricsFollowEvent event) {
    _resumeTimer?.cancel();
    if (shouldArmResumeTimer(state, event)) {
      _resumeTimer = Timer(
        kLyricsAutoResumeDelay,
        () => dispatch(LyricsFollowEvent.autoResumeElapsed),
      );
    }
    state = nextFollowState(state, event);
  }
}
