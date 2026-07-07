import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/tag_encoding.dart';
import 'package:viby/data/sources/local/id3_reader.dart';

/// Builds a minimal ID3v2.3 tag with a single title frame carrying [body]
/// (already including the leading encoding byte).
Uint8List _id3v2WithTitle(List<int> frameBody) {
  final List<int> frame = <int>[
    ...'TIT2'.codeUnits,
    0, 0, 0, frameBody.length, // size, big-endian (small enough for one byte)
    0, 0, // flags
    ...frameBody,
  ];
  return Uint8List.fromList(<int>[
    ...'ID3'.codeUnits,
    3, 0, // v2.3.0
    0, // flags
    0, 0, 0, frame.length, // synchsafe tag size (small)
    ...frame,
  ]);
}

void main() {
  const String arabic = 'بحر';

  test('reads a Latin-1 frame byte-for-byte (preserving CP1256 bytes)', () {
    // encoding 0 (Latin-1) + CP1256 bytes for "بحر".
    final Uint8List bytes = _id3v2WithTitle(<int>[0, 0xC8, 0xCD, 0xD1]);
    final Id3Tags tags = Id3Reader.parse(bytes);
    // The raw read is Latin-1 mojibake...
    expect(tags.title, 'ÈÍÑ');
    // ...which bestDecoding then recovers to real Arabic.
    expect(bestDecoding(tags.title!), arabic);
  });

  test('reads a UTF-8 frame correctly and leaves it untouched', () {
    final Uint8List bytes =
        _id3v2WithTitle(<int>[3, ...utf8.encode(arabic)]); // encoding 3 = UTF-8
    final Id3Tags tags = Id3Reader.parse(bytes);
    expect(tags.title, arabic);
    expect(bestDecoding(tags.title!), arabic);
  });

  test('returns empty tags for non-ID3 bytes without throwing', () {
    expect(Id3Reader.parse(Uint8List.fromList(<int>[1, 2, 3])).isEmpty, isTrue);
    expect(Id3Reader.parse(Uint8List(0)).isEmpty, isTrue);
  });

  test('falls back to ID3v1 for fields v2 lacks', () {
    // 128-byte ID3v1 block: "TAG" + 30-char title/artist/album...
    final List<int> v1 = <int>[
      ...'TAG'.codeUnits,
      ..._padded('My Title', 30),
      ..._padded('My Artist', 30),
      ..._padded('My Album', 30),
      ...List<int>.filled(128 - 3 - 90, 0),
    ];
    final Id3Tags tags = Id3Reader.parse(Uint8List.fromList(v1));
    expect(tags.title, 'My Title');
    expect(tags.artist, 'My Artist');
    expect(tags.album, 'My Album');
  });
}

List<int> _padded(String s, int len) {
  final List<int> b = List<int>.from(s.codeUnits);
  return <int>[...b, ...List<int>.filled(len - b.length, 0)];
}
