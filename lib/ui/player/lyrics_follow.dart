/// Pure state machine for the lyrics auto-follow override.
///
/// While `following`, the expanded lyrics view auto-scrolls to keep the active
/// line in view. When the user scrolls the lyrics manually it flips to `paused`
/// (a "resume" pill appears and auto-scroll stops); it returns to `following`
/// when the user taps resume, when a 4s idle timer fires after scrolling ends,
/// or when the track changes. The timer itself is a side effect owned by the
/// controller — this module is the pure transition table so the behaviour is
/// unit-testable.
library;

/// The two follow modes.
enum LyricsFollow { following, paused }

/// Events that drive the follow state.
enum LyricsFollowEvent {
  /// The user is actively scrolling the lyrics list.
  userScrolled,

  /// Scrolling settled (the idle timer should be (re)started by the controller).
  scrollSettled,

  /// The 4s idle timer elapsed.
  autoResumeElapsed,

  /// The user tapped the "resume" pill.
  resumeTapped,

  /// The current track changed (reset to following).
  trackChanged,
}

/// Immutable follow state. [showResumePill] and [isFollowing] are derived so the
/// UI never branches on the raw enum.
class LyricsFollowState {
  const LyricsFollowState(this.mode);
  const LyricsFollowState.following() : mode = LyricsFollow.following;

  final LyricsFollow mode;

  bool get isFollowing => mode == LyricsFollow.following;
  bool get showResumePill => mode == LyricsFollow.paused;

  @override
  bool operator ==(Object other) =>
      other is LyricsFollowState && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

/// How long after the user stops scrolling before auto-follow resumes.
const Duration kLyricsAutoResumeDelay = Duration(seconds: 4);

/// Pure transition: the next follow state given [state] and [event].
///
/// `scrollSettled` intentionally does not change the state — it stays `paused`
/// while the controller (re)arms the idle timer; only `autoResumeElapsed`,
/// `resumeTapped`, or `trackChanged` return to `following`.
LyricsFollowState nextFollowState(
  LyricsFollowState state,
  LyricsFollowEvent event,
) {
  switch (event) {
    case LyricsFollowEvent.userScrolled:
      return const LyricsFollowState(LyricsFollow.paused);
    case LyricsFollowEvent.scrollSettled:
      return state;
    case LyricsFollowEvent.autoResumeElapsed:
    case LyricsFollowEvent.resumeTapped:
    case LyricsFollowEvent.trackChanged:
      return const LyricsFollowState(LyricsFollow.following);
  }
}

/// Whether, after applying [event] from [before], the controller should (re)start
/// the 4s idle timer. True only when scrolling settles while paused — every
/// other event cancels/omits the timer.
bool shouldArmResumeTimer(LyricsFollowState before, LyricsFollowEvent event) {
  return event == LyricsFollowEvent.scrollSettled &&
      before.mode == LyricsFollow.paused;
}
