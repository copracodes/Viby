import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/fade_envelope.dart';
import 'package:viby/audio/volume_mixer.dart';

/// Advance [env] by [total], one [kFadeTick] at a time — the same cadence the
/// handler's ticker uses. Returns the value after the last step.
double _tick(FadeEnvelope env, Duration total) {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    env.advance(kFadeTick);
    elapsed += kFadeTick;
  }
  return env.value;
}

void main() {
  group('FadeEnvelope — resume fade-in', () {
    test('resume from a paused state fades in from 0 to exactly 1.0', () {
      final env = FadeEnvelope();
      env.resume(kResumeFadeIn, wasPlaying: false);

      // Drops to silence immediately, then climbs.
      expect(env.value, 0.0);
      expect(env.ramping, isTrue);

      // Mid-ramp it is strictly between 0 and 1.
      _tick(env, const Duration(milliseconds: 150));
      expect(env.value, greaterThan(0.0));
      expect(env.value, lessThan(1.0));

      // Fully elapsed: lands *exactly* at 1.0 and stops ramping.
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0);
      expect(env.ramping, isFalse);
    });

    test('resume while already playing ramps from current value (no dip to 0)',
        () {
      final env = FadeEnvelope(initial: 0.6);
      env.resume(kResumeFadeIn, wasPlaying: true);
      // No dip: it never drops below where it was.
      expect(env.value, 0.6);
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0);
    });

    test('over-advancing never overshoots 1.0', () {
      final env = FadeEnvelope()..resume(kResumeFadeIn, wasPlaying: false);
      _tick(env, kResumeFadeIn * 3);
      expect(env.value, 1.0);
      expect(env.ramping, isFalse);
    });
  });

  group('FadeEnvelope — interruption sequences (the silent-playback bug)', () {
    test('pause mid-ramp then resume converges to 1.0', () {
      final env = FadeEnvelope()..resume(kResumeFadeIn, wasPlaying: false);
      _tick(env, const Duration(milliseconds: 100)); // partway up
      final double frozen = env.value;
      expect(frozen, greaterThan(0.0));
      expect(frozen, lessThan(1.0));

      env.cancel(); // pause: freeze the envelope
      expect(env.ramping, isFalse);
      // A stray advance after cancel does nothing.
      env.advance(kFadeTick);
      expect(env.value, frozen);

      // Resume again (from stopped): re-fades from 0, lands at 1.0.
      env.resume(kResumeFadeIn, wasPlaying: false);
      expect(env.value, 0.0);
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0);
    });

    test('pause-then-wait-then-play (the reported symptom) is never stuck low',
        () {
      // Play, fully ramp up.
      final env = FadeEnvelope()..resume(kResumeFadeIn, wasPlaying: false);
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0);

      // Pause.
      env.cancel();
      // A long "wait" — no ticks, nothing drains the envelope.
      // Play again.
      env.resume(kResumeFadeIn, wasPlaying: false);
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0, reason: 'resume must always reach full level');
    });

    test('cancel with no ramp in flight is a harmless no-op', () {
      final env = FadeEnvelope();
      env.cancel();
      expect(env.value, 1.0);
      expect(env.ramping, isFalse);
    });
  });

  group('FadeEnvelope — sleep-fade cooperation', () {
    test('snap sets the level instantly with no ramp', () {
      final env = FadeEnvelope()..snap(0.4);
      expect(env.value, 0.4);
      expect(env.ramping, isFalse);
    });

    test('ramp restores toward full over its duration', () {
      final env = FadeEnvelope(initial: 0.0)
        ..ramp(1.0, const Duration(milliseconds: 400));
      _tick(env, const Duration(milliseconds: 400));
      expect(env.value, 1.0);
    });

    test('a resume takes over a sleep fade-out cleanly', () {
      final env = FadeEnvelope()..snap(0.3); // mid sleep fade-out
      env.resume(kResumeFadeIn, wasPlaying: true);
      _tick(env, kResumeFadeIn);
      expect(env.value, 1.0);
    });
  });

  group('FadeEnvelope — final-volume invariant (property test)', () {
    test(
        'across random play/pause/tick interleavings, a final resume+settle '
        'always lands at exactly 1.0 (and volume composes with ReplayGain)', () {
      final rng = Random(20260719);
      for (var trial = 0; trial < 2000; trial++) {
        final env = FadeEnvelope();
        bool playing = false;

        // A random storm of toggles and ticks at arbitrary spacing.
        final int ops = rng.nextInt(12);
        for (var i = 0; i < ops; i++) {
          switch (rng.nextInt(3)) {
            case 0: // play / resume
              env.resume(kResumeFadeIn, wasPlaying: playing);
              playing = true;
            case 1: // pause
              env.cancel();
              playing = false;
            case 2: // let some time pass (0..500ms, incl. inside the 300ms ramp)
              _tick(env, Duration(milliseconds: rng.nextInt(500)));
          }
          // The envelope is *always* a valid factor.
          expect(env.value, inInclusiveRange(0.0, 1.0));
        }

        // End state: the user presses play and lets it settle.
        env.resume(kResumeFadeIn, wasPlaying: playing);
        _tick(env, kResumeFadeIn);

        expect(env.value, 1.0,
            reason: 'trial $trial: a settled resume must reach full level');

        // And the mixer composes it with a ReplayGain scalar exactly (target is
        // the RG level, not a hard-coded 1.0).
        const double rg = 0.72;
        expect(
          mixVolume(gain: rg, duck: 1.0, fade: env.value),
          closeTo(rg, 1e-9),
        );
      }
    });
  });
}
