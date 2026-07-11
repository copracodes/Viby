import 'lyrics.dart';

/// The index of the **active** lyric line for playback position [positionMs]:
/// the last line whose `startMs <= positionMs`. Returns `-1` before the first
/// line's time (nothing highlighted yet) and for an empty list.
///
/// [lines] must be sorted ascending by `startMs` (the parser guarantees this),
/// so this is an O(log n) binary search — cheap enough to run on every throttled
/// position tick. The caller exposes the result as a narrow `int` provider so a
/// tick that doesn't cross a line boundary triggers no rebuild.
int activeLineIndexFor(List<LyricLine> lines, int positionMs) {
  if (lines.isEmpty) return -1;
  if (positionMs < lines.first.startMs) return -1;
  int lo = 0;
  int hi = lines.length - 1;
  int ans = 0;
  while (lo <= hi) {
    final int mid = (lo + hi) >> 1;
    if (lines[mid].startMs <= positionMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
