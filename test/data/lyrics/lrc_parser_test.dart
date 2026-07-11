import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lrc_parser.dart';
import 'package:viby/data/lyrics/lyrics.dart';

/// Reads a committed `.lrc` fixture (relative to the package root, which is the
/// CWD under `flutter test`).
String _fixture(String name) =>
    File('test/data/lyrics/fixtures/$name').readAsStringSync();

void main() {
  group('timestamp variants', () {
    test('parses [mm:ss.xx] centiseconds', () {
      final ParsedLrc r = LrcParser.parse('[00:03.50]Line');
      expect(r.isSynced, isTrue);
      expect(r.lines.single.startMs, 3500);
    });

    test('parses [mm:ss] with no fraction', () {
      expect(LrcParser.parse('[00:07]Line').lines.single.startMs, 7000);
    });

    test('parses [mm:ss.xxx] milliseconds', () {
      expect(LrcParser.parse('[00:20.500]Line').lines.single.startMs, 20500);
    });

    test('parses [mm:ss:xx] colon-separated fraction', () {
      expect(LrcParser.parse('[01:05:10]Line').lines.single.startMs, 65100);
    });

    test('minutes over 59 are allowed', () {
      expect(LrcParser.parse('[75:00.00]Line').lines.single.startMs, 4500000);
    });
  });

  test('multiple timestamps on one line expand to one line each (chorus)', () {
    final ParsedLrc r = LrcParser.parse(_fixture('chorus_multi.lrc'));
    final List<LyricLine> chorus =
        r.lines.where((LyricLine l) => l.text == 'We sing the chorus').toList();
    expect(chorus.map((LyricLine l) => l.startMs), <int>[20000, 40000, 60000]);
    // And they interleave correctly with the verses (sorted by time).
    expect(r.lines.map((LyricLine l) => l.startMs),
        <int>[10000, 20000, 30000, 40000, 60000]);
  });

  test('[offset:+ms] shifts all times earlier (subtracts)', () {
    final ParsedLrc r = LrcParser.parse(_fixture('offset.lrc'));
    // 5000 - 500, 10000 - 500.
    expect(r.lines.map((LyricLine l) => l.startMs), <int>[4500, 9500]);
  });

  test('negative offset shifts later; clamps at zero', () {
    final ParsedLrc r = LrcParser.parse('[offset:-1000]\n[00:00.50]Line');
    // 500 - (-1000) = 1500.
    expect(r.lines.single.startMs, 1500);
    final ParsedLrc clamp = LrcParser.parse('[offset:+9000]\n[00:01.00]Line');
    expect(clamp.lines.single.startMs, 0); // 1000 - 9000 clamps to 0
  });

  test('metadata tags are parsed-and-ignored for display', () {
    final ParsedLrc r = LrcParser.parse(_fixture('basic.lrc'));
    expect(r.isSynced, isTrue);
    expect(r.lines.first.text, 'First line');
    expect(r.lines.map((LyricLine l) => l.text),
        isNot(contains(contains('Test Artist'))));
    expect(r.lines.length, 4);
  });

  test('malformed/untimed lines are skipped in synced mode, then sorted', () {
    final ParsedLrc r = LrcParser.parse(_fixture('messy.lrc'));
    expect(r.isSynced, isTrue);
    // The untimed prose line and the "[garbage tag]" are dropped; the empty
    // [00:25.00] line is retained (musical gap) but has empty text.
    expect(r.lines.map((LyricLine l) => l.startMs),
        <int>[10000, 20500, 25000, 30000]);
    expect(r.lines.first.text, 'Earlier line that sorts first');
    expect(r.lines[2].text, isEmpty); // the bare [00:25.00]
  });

  test('a document with no timestamps is unsynced, order preserved', () {
    final ParsedLrc r = LrcParser.parse(_fixture('unsynced.txt'));
    expect(r.isSynced, isFalse);
    expect(r.lines.every((LyricLine l) => l.startMs == 0), isTrue);
    expect(r.lines.map((LyricLine l) => l.text), <String>[
      'Just some plain lyrics',
      'with no timing information',
      'across several lines',
    ]);
  });

  test('empty / whitespace input yields an empty unsynced result', () {
    expect(LrcParser.parse('').lines, isEmpty);
    expect(LrcParser.parse('   \n  \n').lines, isEmpty);
    expect(LrcParser.parse('').isSynced, isFalse);
  });

  group('enhanced (word-level) LRC', () {
    test('retains word timings but renders line-level display text', () {
      final ParsedLrc r = LrcParser.parse(_fixture('enhanced.lrc'));
      final LyricLine first = r.lines.first;
      expect(first.startMs, 12000);
      // Inline <..> tags stripped from the display text.
      expect(first.text, 'Word by word');
      // ...but retained on the line for a future karaoke mode.
      expect(first.words, <WordTiming>[
        const WordTiming(startMs: 12000, text: 'Word'),
        const WordTiming(startMs: 12500, text: 'by'),
        const WordTiming(startMs: 13000, text: 'word'),
      ]);
    });
  });

  group('decodeBytes', () {
    test('strips a UTF-8 BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xEF, 0xBB, 0xBF, // BOM
        ...'[00:01.00]Hi'.codeUnits,
      ]);
      final String decoded = LrcParser.decodeBytes(bytes);
      expect(decoded.codeUnitAt(0), isNot(0xFEFF));
      expect(LrcParser.parse(decoded).lines.single.text, 'Hi');
    });

    test('decodes valid UTF-8 Arabic directly', () {
      const String arabic = 'أغنية';
      final Uint8List bytes =
          Uint8List.fromList(utf8.encode('[00:01.00]$arabic'));
      final String decoded = LrcParser.decodeBytes(bytes);
      expect(LrcParser.parse(decoded).lines.single.text, arabic);
    });

    test('falls back to CP1256 recovery for legacy Arabic bytes', () {
      // CP1256 bytes for "بحر" (0xC8 0xCD 0xD1), which are NOT valid UTF-8.
      final Uint8List bytes = Uint8List.fromList(<int>[
        ...'[00:02.00]'.codeUnits,
        0xC8, 0xCD, 0xD1,
      ]);
      final String decoded = LrcParser.decodeBytes(bytes);
      // decodeBytes keeps the bytes as Latin-1 code units (invalid UTF-8)...
      final ParsedLrc r = LrcParser.parse(decoded);
      // ...and the parser's per-line bestDecoding recovers real Arabic.
      expect(r.lines.single.startMs, 2000);
      expect(r.lines.single.text, 'بحر');
    });
  });
}
