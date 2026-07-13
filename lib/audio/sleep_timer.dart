import 'dart:math' as math;

/// When the sleep timer should stop playback.
sealed class SleepMode {
  const SleepMode();
}

/// Stop after a wall-clock duration (15 / 30 / 45 / 60 min).
class SleepAfter extends SleepMode {
  const SleepAfter(this.duration);

  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is SleepAfter && other.duration == duration;

  @override
  int get hashCode => duration.hashCode;
}

/// Stop when the current track finishes.
class SleepEndOfTrack extends SleepMode {
  const SleepEndOfTrack();

  @override
  bool operator ==(Object other) => other is SleepEndOfTrack;

  @override
  int get hashCode => 1;
}

/// Stop when the queue runs out (i.e. at the end of the last track).
class SleepEndOfQueue extends SleepMode {
  const SleepEndOfQueue();

  @override
  bool operator ==(Object other) => other is SleepEndOfQueue;

  @override
  int get hashCode => 2;
}

/// How long before the stop the volume starts falling away.
const Duration kSleepFadeOut = Duration(seconds: 10);

/// The presets offered in the UI.
const List<Duration> kSleepPresets = <Duration>[
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
];

/// What the UI shows: the armed mode and how long is left (null = not armed, or
/// armed on a condition with no meaningful countdown yet).
class SleepTimerState {
  const SleepTimerState({this.mode, this.remaining});

  const SleepTimerState.idle()
      : mode = null,
        remaining = null;

  final SleepMode? mode;
  final Duration? remaining;

  bool get isArmed => mode != null;

  /// Whether the fade-out has begun (the chip can show it).
  bool get isFading =>
      remaining != null && remaining! <= kSleepFadeOut && remaining! > Duration.zero;

  @override
  bool operator ==(Object other) =>
      other is SleepTimerState &&
      other.mode == mode &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(mode, remaining);
}

/// How long until the timer fires, from the mode and the playback situation.
///
/// Pure: the whole "when do we stop" policy is this one function, so every mode
/// is testable without a player.
///
/// * [SleepAfter] counts wall-clock down to its deadline — so it keeps running
///   while the track changes, and (because the deadline is absolute) it stays
///   correct across a backgrounded app that stops ticking.
/// * [SleepEndOfTrack] counts down what's left of the current track, which makes
///   the fade-out fall in the track's last seconds instead of chopping it off.
/// * [SleepEndOfQueue] does the same, but only once there is no next track —
///   until then there is nothing to count down and playback continues.
Duration? sleepRemaining({
  required SleepMode? mode,
  required DateTime now,
  DateTime? deadline,
  Duration position = Duration.zero,
  Duration? trackDuration,
  bool hasNext = false,
}) {
  switch (mode) {
    case null:
      return null;
    case SleepAfter():
      if (deadline == null) return null;
      final Duration left = deadline.difference(now);
      return left.isNegative ? Duration.zero : left;
    case SleepEndOfTrack():
      if (trackDuration == null) return null;
      final Duration left = trackDuration - position;
      return left.isNegative ? Duration.zero : left;
    case SleepEndOfQueue():
      if (hasNext || trackDuration == null) return null;
      final Duration left = trackDuration - position;
      return left.isNegative ? Duration.zero : left;
  }
}

/// The fade envelope for [remaining]: 1.0 until the last [kSleepFadeOut], then a
/// linear ramp to 0. Music that fades away beats music that gets cut off — and
/// if you're asleep you'll never hear the difference; if you're not, you won't
/// be startled.
double sleepFadeLevel(Duration? remaining, {Duration window = kSleepFadeOut}) {
  if (remaining == null) return 1;
  if (remaining >= window) return 1;
  if (remaining <= Duration.zero) return 0;
  return math.max(
    0,
    math.min(1, remaining.inMilliseconds / window.inMilliseconds),
  );
}

/// Whether playback should stop now.
bool sleepShouldStop(Duration? remaining) =>
    remaining != null && remaining <= Duration.zero;
