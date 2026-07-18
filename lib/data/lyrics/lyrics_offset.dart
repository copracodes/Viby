/// Applying a manual per-track lyrics sync offset — pure, so the additive
/// semantics are unit-tested independent of the DB and UI.
///
/// The offset is layered **on top of** the parser's own `[offset:]` tag (which
/// is already baked into each [LyricLine.startMs]): a positive value delays the
/// lyrics, a negative one advances them. The two helpers below are inverses, so
/// the highlight and tap-to-seek agree — a line is active exactly when
/// `positionMs >= startMs + offsetMs`.
library;

/// A line's effective start time once the manual [offsetMs] is applied. Used for
/// tap-to-seek (seek to the corrected start). Clamped at 0.
int offsetAdjustedStartMs(int startMs, int offsetMs) {
  final int adjusted = startMs + offsetMs;
  return adjusted < 0 ? 0 : adjusted;
}

/// The playback position to feed the active-line search so a manual [offsetMs]
/// shifts the highlight — the inverse of [offsetAdjustedStartMs], so
/// `activeLineIndexFor(lines, offsetAdjustedQueryMs(pos, off))` lights a line up
/// exactly when `pos >= line.startMs + off`.
int offsetAdjustedQueryMs(int positionMs, int offsetMs) => positionMs - offsetMs;
