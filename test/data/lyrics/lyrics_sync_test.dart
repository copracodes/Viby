import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/lyrics/lyrics_sync.dart';

List<LyricLine> _lines(List<int> starts) =>
    starts.map((int ms) => LyricLine(startMs: ms, text: 't$ms')).toList();

void main() {
  final List<LyricLine> lines = _lines(<int>[1000, 3000, 3000, 7000, 65000]);

  test('empty list has no active line', () {
    expect(activeLineIndexFor(const <LyricLine>[], 5000), -1);
  });

  test('before the first line → -1', () {
    expect(activeLineIndexFor(lines, 0), -1);
    expect(activeLineIndexFor(lines, 999), -1);
  });

  test('exactly on the first line → 0', () {
    expect(activeLineIndexFor(lines, 1000), 0);
  });

  test('between lines → the earlier line', () {
    expect(activeLineIndexFor(lines, 1500), 0);
    expect(activeLineIndexFor(lines, 6999), 2);
  });

  test('exactly on a boundary → that line (last of equal timestamps)', () {
    // Two lines share startMs 3000; the search lands on the last such index.
    expect(activeLineIndexFor(lines, 3000), 2);
    expect(activeLineIndexFor(lines, 7000), 3);
  });

  test('after the last line → the last index', () {
    expect(activeLineIndexFor(lines, 65000), 4);
    expect(activeLineIndexFor(lines, 999999), 4);
  });

  test('single-line list', () {
    final List<LyricLine> one = _lines(<int>[2000]);
    expect(activeLineIndexFor(one, 1000), -1);
    expect(activeLineIndexFor(one, 2000), 0);
    expect(activeLineIndexFor(one, 9000), 0);
  });
}
