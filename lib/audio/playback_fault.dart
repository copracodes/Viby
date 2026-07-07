import '../data/db/tables.dart' show RepeatMode;

/// A playback failure surfaced to the app: a track's file was missing or
/// couldn't be decoded. Domain-only (no just_audio types) so state/UI can react
/// to it through the facade.
class PlaybackFault {
  const PlaybackFault({
    required this.trackId,
    required this.title,
    required this.allFailed,
  });

  /// The track that failed (null if it couldn't be resolved).
  final String? trackId;

  /// Its title, for the "Couldn't play X — skipped" message.
  final String? title;

  /// True when *every* track in the queue has failed in a row, so playback
  /// stopped rather than skipping (the UI shows a terminal message).
  final bool allFailed;
}

/// What playback should do after a track fails to load/decode.
enum FaultOutcome {
  /// Jump to [FaultDecision.skipIndex] and keep playing.
  skip,

  /// Every track failed — stop gracefully.
  stopAllFailed,

  /// Reached the end of the queue with nothing left to try — stop.
  stopEnd,
}

/// The resolved action for a fault. [skipIndex] is set only for [FaultOutcome.skip].
class FaultDecision {
  const FaultDecision(this.outcome, [this.skipIndex]);
  final FaultOutcome outcome;
  final int? skipIndex;
}

/// Pure decision for "a track just failed — now what?". Kept side-effect-free and
/// unit-tested (like `nextIndexAfterEnd`): skip to the next track, wrap under
/// repeat-all, stop when the whole queue has failed, and stop at the end.
///
/// [consecutiveFailures] counts failures since the last track that actually
/// played; once it reaches the queue length we've tried everything and stop.
FaultDecision decidePlaybackFault({
  required int failedIndex,
  required int queueLength,
  required int consecutiveFailures,
  required RepeatMode repeat,
}) {
  if (queueLength <= 0) return const FaultDecision(FaultOutcome.stopEnd);
  if (consecutiveFailures >= queueLength) {
    return const FaultDecision(FaultOutcome.stopAllFailed);
  }
  final int next = failedIndex + 1;
  if (next < queueLength) return FaultDecision(FaultOutcome.skip, next);
  // At the end of the queue.
  if (repeat == RepeatMode.all) return const FaultDecision(FaultOutcome.skip, 0);
  return const FaultDecision(FaultOutcome.stopEnd);
}
