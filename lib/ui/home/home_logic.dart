// Pure Home-screen logic (no widgets), so the section rules are unit-testable.

/// The "Your top tracks" section only appears once there's enough history to be
/// meaningful — otherwise it'd show one or two plays and feel empty.
const int kMinTopTracks = 5;

/// Whether to render the top-tracks section for [distinctPlayedCount] distinct
/// tracks that have been played.
bool shouldShowTopTracks(int distinctPlayedCount) =>
    distinctPlayedCount >= kMinTopTracks;

/// A time-of-day greeting (no emoji, understated). [hour] is 0–23.
String greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 22) return 'Good evening';
  return 'Late night'; // 22:00–04:59
}
