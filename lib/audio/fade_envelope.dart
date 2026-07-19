import 'volume_mixer.dart';

/// The tick interval the audio handler advances a ramp by (~60fps).
const Duration kFadeTick = Duration(milliseconds: 16);

/// The resume/sleep volume *envelope* — the `fade` factor the [mixVolume] mixer
/// multiplies (see `volume_mixer.dart`). A pure, clock-injected state machine
/// (the handler owns the `Timer` that calls [advance]) so the interruption
/// behaviour is unit-testable without just_audio.
///
/// It exists because the resume fade-in used to be entangled with just_audio's
/// `play()` Future, which — on a *resume* — does not complete until the next
/// pause/stop. Scheduling the ramp after `await player.play()` therefore left the
/// envelope stranded at 0 and playback silent while the position advanced. The
/// fix moves all envelope logic here, off the play Future entirely, and pins one
/// invariant:
///
/// > **A [resume] followed by enough [advance] always lands at exactly 1.0.**
///
/// No sequence of [resume]/[cancel] at any timing can strand the envelope low:
/// every resume re-targets full level from wherever the value currently is.
class FadeEnvelope {
  FadeEnvelope({double initial = 1.0})
      : _value = _clamp(initial),
        _target = _clamp(initial),
        _from = _clamp(initial);

  double _value;
  double _target;
  double _from;

  /// Time remaining in the active ramp; `zero` when settled.
  Duration _remaining = Duration.zero;
  Duration _total = Duration.zero;

  /// The current envelope factor, always in [0, 1].
  double get value => _value;

  /// Whether a ramp is in flight (the handler runs its tick timer iff this).
  bool get ramping => _remaining > Duration.zero;

  /// Begin the resume fade-in, always landing at full level (1.0).
  ///
  /// On a genuine resume ([wasPlaying] false — the player was paused/stopped)
  /// the envelope drops to 0 first so the track fades *in*; when already playing
  /// ([wasPlaying] true) it ramps from the current value so there is no dip.
  /// Either way it re-targets 1.0, so it can never be left stranded low.
  void resume(Duration over, {required bool wasPlaying}) {
    if (!wasPlaying) _value = 0.0;
    _rampTo(1.0, over);
  }

  /// Ramp toward [level] over [over] from the current value (the sleep timer's
  /// cancel restore uses this to bring the music back up).
  void ramp(double level, Duration over) => _rampTo(level, over);

  /// Snap straight to [level] with no ramp (sleep fade-out steps; hard resets).
  void snap(double level) {
    _value = _clamp(level);
    _target = _value;
    _from = _value;
    _remaining = Duration.zero;
    _total = Duration.zero;
  }

  /// Cancel any ramp, freezing the value where it is (a pause). The next
  /// [resume] re-fades from 0, so freezing mid-ramp can't leave audio muted.
  void cancel() {
    _remaining = Duration.zero;
    _total = Duration.zero;
    _target = _value;
    _from = _value;
  }

  /// Advance an in-flight ramp by [delta]; returns the (possibly unchanged)
  /// value. A no-op when not [ramping].
  double advance(Duration delta) {
    if (_remaining <= Duration.zero) return _value;
    _remaining -= delta;
    if (_remaining <= Duration.zero) {
      _value = _target;
      _remaining = Duration.zero;
      _total = Duration.zero;
    } else {
      final double t = 1.0 - _remaining.inMicroseconds / _total.inMicroseconds;
      _value = _clamp(_from + (_target - _from) * t);
    }
    return _value;
  }

  void _rampTo(double target, Duration over) {
    _target = _clamp(target);
    _from = _value;
    if (over <= Duration.zero || _from == _target) {
      _value = _target;
      _remaining = Duration.zero;
      _total = Duration.zero;
      return;
    }
    _total = over;
    _remaining = over;
  }

  static double _clamp(double v) => v.clamp(0.0, 1.0);
}
