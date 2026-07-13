/// The one place the player's volume is decided.
///
/// Three independent things want to move the volume and they must not fight:
///
/// * **gain** — the ReplayGain scalar for the current track (see
///   `replay_gain.dart`). Changes on track load and when settings change.
/// * **duck** — an audio-session interruption (a navigation prompt ducks us to
///   0.3, then restores).
/// * **fade** — a short envelope: 0→1 when resuming from pause, and 1→0 over the
///   sleep timer's last seconds.
///
/// Each owns its own factor and the mixer multiplies them, so a fade-in resumes
/// *to the track's normalized level* rather than to 1.0 (which would undo
/// ReplayGain every time you hit play), and a duck during a fade doesn't cancel
/// either. This is the only function that may compute a volume.
///
/// EQ composes with this by construction: the equalizer/loudness effects live in
/// the just_audio [AudioPipeline] and this scales the player's output volume —
/// different stages, so neither overwrites the other.
double mixVolume({
  required double gain,
  required double duck,
  required double fade,
}) {
  return (gain * duck * fade).clamp(0.0, 1.0);
}

/// Volume factors while ducked by a transient interruption.
const double kDuckFactor = 0.3;

/// How long a resume-from-pause takes to reach full level. Long enough to kill
/// the jarring blast, short enough that play still feels instant.
const Duration kResumeFadeIn = Duration(milliseconds: 300);
