/// Formats a track length in milliseconds as `m:ss` (or `h:mm:ss` past an
/// hour). Shared by track rows, the mini-player and Now Playing.
String formatTrackDuration(int milliseconds) {
  final Duration d = Duration(milliseconds: milliseconds);
  String two(int n) => n.toString().padLeft(2, '0');
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  final String seconds = two(d.inSeconds.remainder(60));
  return hours > 0 ? '$hours:${two(minutes)}:$seconds' : '$minutes:$seconds';
}
