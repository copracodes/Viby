import '../db/tables.dart' show LyricsSource;

export '../db/tables.dart' show LyricsSource;

/// One inline word timing inside an enhanced (word-level) LRC line — the
/// `<mm:ss.xx>` tags that precede each word. The parser **retains** these so a
/// future karaoke mode (v1.1) can highlight word-by-word; v1 renders lines only,
/// so [LyricLine.words] is populated but unused by the current UI.
class WordTiming {
  const WordTiming({required this.startMs, required this.text});

  final int startMs;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is WordTiming && other.startMs == startMs && other.text == text;

  @override
  int get hashCode => Object.hash(startMs, text);

  @override
  String toString() => 'WordTiming($startMs, "$text")';
}

/// A single displayable lyric line.
///
/// [startMs] is the (offset-applied) time the line becomes active; it is `0` for
/// every line of an unsynced document. [words] carries enhanced-LRC word timings
/// when present (empty otherwise).
class LyricLine {
  const LyricLine({
    required this.startMs,
    required this.text,
    this.words = const <WordTiming>[],
  });

  final int startMs;
  final String text;
  final List<WordTiming> words;

  @override
  bool operator ==(Object other) =>
      other is LyricLine &&
      other.startMs == startMs &&
      other.text == text &&
      _sameWords(other.words, words);

  @override
  int get hashCode => Object.hash(startMs, text, Object.hashAll(words));

  static bool _sameWords(List<WordTiming> a, List<WordTiming> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'LyricLine($startMs, "$text")';
}

/// A fully resolved + parsed lyrics document for one track.
///
/// [isSynced] gates the two UI modes: synced → the scrolling/highlighting view
/// with tap-to-seek; unsynced → static scrollable text. [source] records where
/// the lyrics came from (drives the "not synced" caption and cache bookkeeping).
class Lyrics {
  const Lyrics({
    required this.lines,
    required this.isSynced,
    required this.source,
  });

  /// The graceful empty state — no lyrics found for the track.
  const Lyrics.none()
      : lines = const <LyricLine>[],
        isSynced = false,
        source = LyricsSource.none;

  final List<LyricLine> lines;
  final bool isSynced;
  final LyricsSource source;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  @override
  String toString() =>
      'Lyrics(${lines.length} lines, synced=$isSynced, source=$source)';
}
