import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/player/lyrics_follow.dart';

void main() {
  const LyricsFollowState following = LyricsFollowState.following();
  const LyricsFollowState paused = LyricsFollowState(LyricsFollow.paused);

  group('nextFollowState transitions', () {
    test('user scrolling pauses auto-follow (pill shows)', () {
      final LyricsFollowState next =
          nextFollowState(following, LyricsFollowEvent.userScrolled);
      expect(next.isFollowing, isFalse);
      expect(next.showResumePill, isTrue);
    });

    test('scroll settling keeps it paused (timer arms separately)', () {
      expect(nextFollowState(paused, LyricsFollowEvent.scrollSettled), paused);
    });

    test('the idle timer elapsing resumes following', () {
      final LyricsFollowState next =
          nextFollowState(paused, LyricsFollowEvent.autoResumeElapsed);
      expect(next.isFollowing, isTrue);
      expect(next.showResumePill, isFalse);
    });

    test('tapping resume returns to following immediately', () {
      expect(nextFollowState(paused, LyricsFollowEvent.resumeTapped), following);
    });

    test('a track change resets to following', () {
      expect(nextFollowState(paused, LyricsFollowEvent.trackChanged), following);
    });
  });

  group('shouldArmResumeTimer', () {
    test('arms only when scrolling settles while paused', () {
      expect(shouldArmResumeTimer(paused, LyricsFollowEvent.scrollSettled),
          isTrue);
    });

    test('does not arm on settle when already following', () {
      expect(shouldArmResumeTimer(following, LyricsFollowEvent.scrollSettled),
          isFalse);
    });

    test('does not arm on active scrolling (user still interacting)', () {
      expect(
          shouldArmResumeTimer(paused, LyricsFollowEvent.userScrolled), isFalse);
    });

    test('does not arm on resume/track-change', () {
      expect(
          shouldArmResumeTimer(paused, LyricsFollowEvent.resumeTapped), isFalse);
      expect(shouldArmResumeTimer(paused, LyricsFollowEvent.trackChanged),
          isFalse);
    });
  });
}
