import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/tag_encoding.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/lyrics/lyrics_repository.dart';
import 'package:viby/data/lyrics/sources/embedded_lyrics_source.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/data/sources/local/id3_reader.dart';

// --- ID3v2.3 tag builders (plain uint32 frame size, synchsafe tag size) ---

const List<int> _eng = <int>[0x65, 0x6e, 0x67]; // "eng"

List<int> _synchsafe(int n) =>
    <int>[(n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f];

List<int> _u32(int n) =>
    <int>[(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];

List<int> _frame(String id, List<int> body) =>
    <int>[...id.codeUnits, ..._u32(body.length), 0, 0, ...body];

Uint8List _tag(List<List<int>> frames) {
  final List<int> body = <int>[for (final List<int> f in frames) ...f];
  return Uint8List.fromList(<int>[
    ...'ID3'.codeUnits, 3, 0, 0, // v2.3.0, no flags
    ..._synchsafe(body.length),
    ...body,
  ]);
}

/// A USLT frame body: enc + "eng" + null-terminated descriptor + text.
List<int> _uslt(int enc, List<int> descriptor, List<int> text) =>
    <int>[enc, ..._eng, ...descriptor, ...text];

class _FakeTagReader implements Id3TagBytesReader {
  _FakeTagReader(this.bytes);
  final Uint8List? bytes;
  @override
  Future<Uint8List?> readId3Tag(String path) async => bytes;
}

const Track _track = Track(
  id: 'local:1',
  source: TrackSource.local,
  title: 'T',
  albumId: 'a',
  artistId: 'ar',
  filePath: '/music/song.mp3',
);

void main() {
  group('USLT (unsynced)', () {
    test('reads Latin-1 text with an empty descriptor', () {
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT', _uslt(0, <int>[0x00], 'hello world'.codeUnits)),
      ]);
      final EmbeddedLyrics emb = Id3Reader.parseLyrics(tag);
      expect(emb.unsyncedText, 'hello world');
      expect(emb.syncedEntries, isNull);
    });

    test('skips a non-empty descriptor before the text', () {
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT',
            _uslt(0, <int>[...'desc'.codeUnits, 0x00], 'the lyrics'.codeUnits)),
      ]);
      expect(Id3Reader.parseLyrics(tag).unsyncedText, 'the lyrics');
    });

    test('preserves Latin-1 bytes so CP1256 Arabic recovers downstream', () {
      // CP1256 bytes for "بحر".
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT', _uslt(0, <int>[0x00], <int>[0xC8, 0xCD, 0xD1])),
      ]);
      final String raw = Id3Reader.parseLyrics(tag).unsyncedText!;
      expect(raw, 'ÈÍÑ'); // byte-preserved mojibake
      expect(bestDecoding(raw), 'بحر'); // recovered
    });

    test('decodes UTF-8 text (encoding 3)', () {
      const String arabic = 'مرحبا';
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT', _uslt(3, <int>[0x00], utf8.encode(arabic))),
      ]);
      expect(Id3Reader.parseLyrics(tag).unsyncedText, arabic);
    });
  });

  group('SYLT (synced)', () {
    List<int> syltMs(List<(int, String)> entries) {
      final List<int> body = <int>[
        0, ..._eng, // enc Latin-1, lang
        2, // time format = absolute milliseconds
        1, // content type = lyrics
        0x00, // empty descriptor
      ];
      for (final (int ms, String text) in entries) {
        body.addAll(text.codeUnits);
        body.add(0x00);
        body.addAll(_u32(ms));
      }
      return body;
    }

    test('parses millisecond entries and serializes to LRC', () {
      final Uint8List tag = _tag(<List<int>>[
        _frame('SYLT', syltMs(<(int, String)>[(1000, 'la'), (2000, 'la la')])),
      ]);
      final EmbeddedLyrics emb = Id3Reader.parseLyrics(tag);
      expect(emb.syncedEntries, isNotNull);
      expect(emb.syncedEntries!.map((SyltEntry e) => e.timeMs), <int>[1000, 2000]);
      expect(emb.syncedEntries!.map((SyltEntry e) => e.text), <String>['la', 'la la']);
      expect(syltToLrc(emb.syncedEntries!), '[00:01.00]la\n[00:02.00]la la\n');
    });

    test('rejects MPEG-frame timing (unsupported → null)', () {
      final List<int> body = <int>[
        0, ..._eng,
        1, // time format = MPEG frames (unsupported)
        1, 0x00,
        ...'la'.codeUnits, 0x00, ..._u32(5),
      ];
      final Uint8List tag = _tag(<List<int>>[_frame('SYLT', body)]);
      expect(Id3Reader.parseLyrics(tag).syncedEntries, isNull);
    });
  });

  group('EmbeddedLyricsSource', () {
    test('prefers SYLT over USLT when both present', () async {
      final List<int> sylt = <int>[
        0, ..._eng, 2, 1, 0x00,
        ...'x'.codeUnits, 0x00, ..._u32(1000),
      ];
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT', _uslt(0, <int>[0x00], 'unsynced'.codeUnits)),
        _frame('SYLT', sylt),
      ]);
      final EmbeddedLyricsSource source =
          EmbeddedLyricsSource(reader: _FakeTagReader(tag));
      final RawLyrics? raw = await source.resolve(_track);
      expect(raw!.source, LyricsSource.embeddedSynced);
      expect(raw.text, contains('[00:01.00]x'));
    });

    test('returns unsynced USLT when no SYLT present', () async {
      final Uint8List tag = _tag(<List<int>>[
        _frame('USLT', _uslt(0, <int>[0x00], 'just words'.codeUnits)),
      ]);
      final EmbeddedLyricsSource source =
          EmbeddedLyricsSource(reader: _FakeTagReader(tag));
      final RawLyrics? raw = await source.resolve(_track);
      expect(raw!.source, LyricsSource.embeddedUnsynced);
      expect(raw.text, 'just words');
    });

    test('returns null when there is no ID3 tag', () async {
      final EmbeddedLyricsSource source =
          EmbeddedLyricsSource(reader: _FakeTagReader(null));
      expect(await source.resolve(_track), isNull);
    });

    test('returns null for a subsonic track (no local file)', () async {
      const Track remote = Track(
        id: 'subsonic:s:1',
        source: TrackSource.subsonic,
        title: 'T',
        albumId: 'a',
        artistId: 'ar',
      );
      final EmbeddedLyricsSource source = EmbeddedLyricsSource(
        reader: _FakeTagReader(Uint8List.fromList(<int>[1, 2, 3])),
      );
      expect(await source.resolve(remote), isNull);
    });
  });
}
