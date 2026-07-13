import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/replay_gain.dart';
import 'package:viby/audio/volume_mixer.dart';

/// The linear scalar a gain in dB should produce (the definition we're pinning).
double _linear(double db) => math.pow(10, db / 20).toDouble();

void main() {
  const ReplayGainInfo loud = ReplayGainInfo(
    trackGainDb: -9.0, // a hot master: pull it DOWN
    trackPeak: 1.0,
    albumGainDb: -8.0,
    albumPeak: 1.0,
  );
  const ReplayGainInfo quiet = ReplayGainInfo(
    trackGainDb: -1.0,
    trackPeak: 0.5,
    albumGainDb: -2.0,
    albumPeak: 0.5,
  );

  group('mode', () {
    test('off never touches the volume, tagged or not', () {
      expect(replayGainScalar(loud, const ReplayGainSettings()), 1.0);
      expect(
        replayGainScalar(
          loud,
          const ReplayGainSettings(preampDb: 6),
        ),
        1.0,
      );
    });

    test('track mode applies the track gain', () {
      expect(
        replayGainScalar(
          loud,
          const ReplayGainSettings(mode: ReplayGainMode.track),
        ),
        closeTo(_linear(-9), 1e-9),
      );
    });

    test('album mode applies the album gain', () {
      expect(
        replayGainScalar(
          loud,
          const ReplayGainSettings(mode: ReplayGainMode.album),
        ),
        closeTo(_linear(-8), 1e-9),
      );
    });

    test('album mode falls back to the track gain when there is no album tag',
        () {
      const ReplayGainInfo trackOnly = ReplayGainInfo(trackGainDb: -5);
      expect(
        replayGainScalar(
          trackOnly,
          const ReplayGainSettings(mode: ReplayGainMode.album),
        ),
        closeTo(_linear(-5), 1e-9),
      );
    });

    test('the loud track ends up quieter than the quiet one (the whole point)',
        () {
      const ReplayGainSettings on =
          ReplayGainSettings(mode: ReplayGainMode.track);
      expect(replayGainScalar(loud, on), lessThan(replayGainScalar(quiet, on)));
    });
  });

  group('untagged files', () {
    test('play untouched — no fabricated level, and no pre-amp either', () {
      expect(
        replayGainScalar(
          null,
          const ReplayGainSettings(mode: ReplayGainMode.track, preampDb: 6),
        ),
        1.0,
      );
      expect(
        replayGainScalar(
          const ReplayGainInfo(),
          const ReplayGainSettings(mode: ReplayGainMode.album, preampDb: -6),
        ),
        1.0,
      );
    });

    test('a peak-only file still gets clip protection when asked', () {
      // No gain to apply, but its own peak says it would clip at unity.
      const ReplayGainInfo peakOnly = ReplayGainInfo(trackPeak: 1.25);
      expect(
        replayGainScalar(
          peakOnly,
          const ReplayGainSettings(mode: ReplayGainMode.track),
        ),
        closeTo(1 / 1.25, 1e-9),
      );
      expect(
        replayGainScalar(
          peakOnly,
          const ReplayGainSettings(
            mode: ReplayGainMode.track,
            preventClipping: false,
          ),
        ),
        1.0,
      );
    });
  });

  group('pre-amp', () {
    test('adds to the file gain in dB (not multiplied)', () {
      expect(
        replayGainScalar(
          loud,
          const ReplayGainSettings(mode: ReplayGainMode.track, preampDb: 3),
        ),
        closeTo(_linear(-6), 1e-9),
      );
    });

    test('a boost cannot push the scalar above unity (volume is an attenuator)',
        () {
      const ReplayGainInfo nearRef =
          ReplayGainInfo(trackGainDb: -1, trackPeak: 0.1);
      expect(
        replayGainScalar(
          nearRef,
          const ReplayGainSettings(mode: ReplayGainMode.track, preampDb: 6),
        ),
        1.0,
      );
    });

    test('a deep cut stays in range', () {
      const ReplayGainInfo veryLoud = ReplayGainInfo(trackGainDb: -20);
      final double s = replayGainScalar(
        veryLoud,
        const ReplayGainSettings(mode: ReplayGainMode.track, preampDb: -6),
      );
      expect(s, closeTo(_linear(-26), 1e-9));
      expect(s, greaterThan(0));
      expect(s, lessThan(1));
    });
  });

  group('clip protection', () {
    test('caps the scalar at 1/peak', () {
      // +6 dB of pre-amp on a -1 dB track would exceed unity; the 0.8 peak caps
      // it at 1/0.8 = 1.25 — which then clamps to 1.0 anyway.
      const ReplayGainInfo info =
          ReplayGainInfo(trackGainDb: 3, trackPeak: 2.0);
      expect(
        replayGainScalar(
          info,
          const ReplayGainSettings(mode: ReplayGainMode.track),
        ),
        closeTo(0.5, 1e-9), // 1/2.0 wins over the +3 dB boost
      );
    });

    test('is skipped when the user turns it off', () {
      const ReplayGainInfo info =
          ReplayGainInfo(trackGainDb: -3, trackPeak: 2.0);
      expect(
        replayGainScalar(
          info,
          const ReplayGainSettings(
            mode: ReplayGainMode.track,
            preventClipping: false,
          ),
        ),
        closeTo(_linear(-3), 1e-9),
      );
    });

    test('album mode uses the album peak, falling back to the track peak', () {
      const ReplayGainInfo info = ReplayGainInfo(
        trackGainDb: 0,
        trackPeak: 4.0,
        albumGainDb: 0,
        albumPeak: 2.0,
      );
      expect(
        replayGainScalar(
          info,
          const ReplayGainSettings(mode: ReplayGainMode.album),
        ),
        closeTo(0.5, 1e-9), // the ALBUM peak
      );
      expect(
        replayGainScalar(
          info,
          const ReplayGainSettings(mode: ReplayGainMode.track),
        ),
        closeTo(0.25, 1e-9), // the TRACK peak
      );
    });

    test('a nonsense peak (<= 0) is ignored rather than dividing by zero', () {
      const ReplayGainInfo info =
          ReplayGainInfo(trackGainDb: -6, trackPeak: 0);
      expect(
        replayGainScalar(
          info,
          const ReplayGainSettings(mode: ReplayGainMode.track),
        ),
        closeTo(_linear(-6), 1e-9),
      );
    });
  });

  group('composition with the fade and the duck (mixVolume)', () {
    test('a resume fade ramps up TO the normalized level, never past it', () {
      final double gain = replayGainScalar(
        loud,
        const ReplayGainSettings(mode: ReplayGainMode.track),
      );

      // Mid-fade: half of the track's level, not half of full scale.
      expect(
        mixVolume(gain: gain, duck: 1, fade: 0.5),
        closeTo(gain * 0.5, 1e-9),
      );
      // Fade complete: exactly the ReplayGain level — the fade must not undo it.
      expect(mixVolume(gain: gain, duck: 1, fade: 1), closeTo(gain, 1e-9));
      // Fade start: silent.
      expect(mixVolume(gain: gain, duck: 1, fade: 0), 0);
    });

    test('a duck during a fade multiplies both, and neither is lost', () {
      expect(
        mixVolume(gain: 0.5, duck: kDuckFactor, fade: 0.5),
        closeTo(0.5 * 0.3 * 0.5, 1e-9),
      );
    });

    test('the sleep fade-out scales the normalized level down to silence', () {
      final double gain = replayGainScalar(
        quiet,
        const ReplayGainSettings(mode: ReplayGainMode.album),
      );
      expect(mixVolume(gain: gain, duck: 1, fade: 1), closeTo(gain, 1e-9));
      expect(mixVolume(gain: gain, duck: 1, fade: 0), 0);
    });

    test('the result never leaves [0, 1] even if a factor misbehaves', () {
      expect(mixVolume(gain: 2, duck: 2, fade: 2), 1.0);
      expect(mixVolume(gain: -1, duck: 1, fade: 1), 0.0);
    });
  });
}
