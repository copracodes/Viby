import 'dart:convert';
import 'dart:typed_data';

import '../../core/tag_encoding.dart';
import 'lyrics.dart';

/// The line-level result of parsing an LRC / plain-text lyrics document.
class ParsedLrc {
  const ParsedLrc({required this.lines, required this.isSynced});

  const ParsedLrc.empty()
      : lines = const <LyricLine>[],
        isSynced = false;

  final List<LyricLine> lines;
  final bool isSynced;

  bool get isEmpty => lines.isEmpty;
}

/// A pure, dependency-free parser for `.lrc` (and plain-text) lyrics.
///
/// Real-world `.lrc` is messy, so the parser is deliberately forgiving:
/// malformed lines are skipped, never fatal; decreasing timestamps are tolerated
/// (the result is sorted); repeated-chorus lines carrying multiple timestamps are
/// expanded into one [LyricLine] per timestamp; `[offset:±ms]` is applied
/// globally; `[ar:]/[ti:]/[al:]/[by:]` metadata is parsed-and-ignored for
/// display. Enhanced (word-level) `<mm:ss.xx>` tags are parsed and **retained**
/// on the line (v1 renders line-level only — see [WordTiming]).
///
/// Legacy-codepage lyrics (Arabic `.lrc` whose bytes are Windows-1256 decoded as
/// Latin-1) are repaired per line through the shared [bestDecoding] heuristic —
/// the same pathway used for mojibake tags — so we never duplicate that decoder.
class LrcParser {
  const LrcParser._();

  /// A leading `[mm:ss.xx]` (or `.xxx` / `:xx`) time tag.
  static final RegExp _timeTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// A `[key:value]` metadata / offset tag (alphabetic key — distinguishes it
  /// from a numeric time tag).
  static final RegExp _metaTag = RegExp(r'\[([a-zA-Z]+):([^\]]*)\]');

  /// An inline enhanced word tag `<mm:ss.xx>`.
  static final RegExp _wordTag =
      RegExp(r'<(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?>');

  /// Parses raw lyrics [text] into line-level [ParsedLrc].
  ///
  /// If any timestamped line is found the document is treated as **synced**
  /// (only timed lines are emitted, sorted by time); otherwise it is **unsynced**
  /// (every non-blank line is emitted in order at `startMs = 0`).
  static ParsedLrc parse(String text) {
    final String cleaned = _stripBom(text);
    final List<String> rawLines = const LineSplitter().convert(cleaned);

    int offsetMs = 0;
    final List<LyricLine> timed = <LyricLine>[];
    final List<String> plain = <String>[];
    bool sawTimestamp = false;

    for (final String rawLine in rawLines) {
      // Pull any [key:value] metadata first (only [offset:] affects output).
      for (final RegExpMatch m in _metaTag.allMatches(rawLine)) {
        if (m.group(1)!.toLowerCase() == 'offset') {
          offsetMs = int.tryParse(m.group(2)!.trim()) ?? offsetMs;
        }
      }

      final List<int> starts = <int>[];
      for (final RegExpMatch m in _timeTag.allMatches(rawLine)) {
        starts.add(_timeToMs(m));
      }

      // The lyric text is whatever remains once time + metadata tags are removed.
      final String body = rawLine
          .replaceAll(_timeTag, '')
          .replaceAll(_metaTag, '')
          .trim();

      if (starts.isEmpty) {
        // No timestamp: candidate unsynced line (kept only if the whole doc is
        // unsynced). Metadata-only lines collapse to empty and are dropped.
        if (body.isNotEmpty) plain.add(_repair(body));
        continue;
      }

      sawTimestamp = true;
      final List<WordTiming> words = _parseWords(body);
      final String display = _repair(_stripWordTags(body));
      for (final int start in starts) {
        timed.add(LyricLine(startMs: start, text: display, words: words));
      }
    }

    if (sawTimestamp) {
      final List<LyricLine> lines = timed
          .map((LyricLine l) => LyricLine(
                startMs: (l.startMs - offsetMs).clamp(0, 1 << 31),
                text: l.text,
                words: l.words,
              ))
          .toList()
        // Stable sort so equal-time chorus lines keep insertion order.
        ..sort((LyricLine a, LyricLine b) => a.startMs.compareTo(b.startMs));
      return ParsedLrc(lines: lines, isSynced: true);
    }

    return ParsedLrc(
      lines: plain
          .map((String t) => LyricLine(startMs: 0, text: t))
          .toList(growable: false),
      isSynced: false,
    );
  }

  /// Decodes raw lyrics [bytes] to a String, mirroring the mojibake pathway:
  /// strip a UTF-8/UTF-16 BOM, try strict UTF-8, and on failure fall back to
  /// Latin-1 (bytes preserved) so [parse]'s per-line [bestDecoding] can recover
  /// Windows-1256 Arabic. This is where a file's bytes become text; [parse]
  /// itself takes an already-decoded String.
  static String decodeBytes(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    // UTF-16 BOM → decode as UTF-16 (rare for .lrc but cheap to honour).
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      return _decodeUtf16(bytes);
    }
    // Skip a UTF-8 BOM if present.
    int start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final Uint8List body = start == 0
        ? bytes
        : Uint8List.sublistView(bytes, start);
    try {
      return utf8.decode(body); // strict: throws on invalid UTF-8
    } on FormatException {
      // Not valid UTF-8 → treat as a legacy codepage: keep bytes as code units
      // so [bestDecoding] can reinterpret them as CP1256 per line.
      return String.fromCharCodes(body);
    }
  }

  // --- helpers ------------------------------------------------------------

  static int _timeToMs(RegExpMatch m) {
    final int minutes = int.parse(m.group(1)!);
    final int seconds = int.parse(m.group(2)!);
    final String? frac = m.group(3);
    int fracMs = 0;
    if (frac != null && frac.isNotEmpty) {
      // 2 digits → centiseconds (×10), 3 → ms (×1), 1 → ×100.
      fracMs = int.parse(frac) * _pow10(3 - frac.length);
    }
    return (minutes * 60 + seconds) * 1000 + fracMs;
  }

  static int _pow10(int n) {
    switch (n) {
      case 0:
        return 1;
      case 1:
        return 10;
      case 2:
        return 100;
      default:
        return 1;
    }
  }

  static List<WordTiming> _parseWords(String body) {
    final List<WordTiming> words = <WordTiming>[];
    int lastEnd = 0;
    int? pendingStart;
    for (final RegExpMatch m in _wordTag.allMatches(body)) {
      if (pendingStart != null) {
        final String word = body.substring(lastEnd, m.start).trim();
        if (word.isNotEmpty) {
          words.add(WordTiming(startMs: pendingStart, text: _repair(word)));
        }
      }
      pendingStart = _timeToMs(m);
      lastEnd = m.end;
    }
    if (pendingStart != null && lastEnd < body.length) {
      final String word = body.substring(lastEnd).trim();
      if (word.isNotEmpty) {
        words.add(WordTiming(startMs: pendingStart, text: _repair(word)));
      }
    }
    return words;
  }

  static String _stripWordTags(String body) =>
      body.replaceAll(_wordTag, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Runs a line's display text through the shared mojibake heuristic. Clean
  /// ASCII/UTF-8 is returned untouched (the heuristic self-guards); only genuine
  /// Latin-1-as-CP1256 Arabic is repaired.
  static String _repair(String s) => bestDecoding(s);

  static String _stripBom(String s) =>
      s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF ? s.substring(1) : s;

  static String _decodeUtf16(Uint8List bytes) {
    final bool big = bytes[0] == 0xFE && bytes[1] == 0xFF;
    final StringBuffer out = StringBuffer();
    for (int i = 2; i + 1 < bytes.length; i += 2) {
      final int unit =
          big ? (bytes[i] << 8) | bytes[i + 1] : (bytes[i + 1] << 8) | bytes[i];
      out.writeCharCode(unit);
    }
    return out.toString();
  }
}
