import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/sources/local/id3_reader.dart';
import 'package:viby/data/sources/local/replay_gain_scanner.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

/// Builds a minimal ID3v2.3 tag containing the given frames.
Uint8List _tag(List<(String id, List<int> body)> frames) {
  final List<int> out = <int>[];
  for (final (String id, List<int> body) in frames) {
    out.addAll(id.codeUnits);
    final int n = body.length;
    out.addAll(<int>[
      (n >> 24) & 0xFF,
      (n >> 16) & 0xFF,
      (n >> 8) & 0xFF,
      n & 0xFF,
    ]);
    out.addAll(<int>[0, 0]); // flags
    out.addAll(body);
  }
  final int size = out.length;
  // synchsafe size (7 bits per byte)
  final List<int> header = <int>[
    0x49, 0x44, 0x33, // "ID3"
    3, 0, // v2.3
    0, // flags
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ];
  return Uint8List.fromList(<int>[...header, ...out]);
}

/// A TXXX frame body: encoding(0 = Latin-1) + description + NUL + value.
List<int> _txxx(String description, String value) =>
    <int>[0, ...description.codeUnits, 0, ...value.codeUnits];

class _FakeReader implements RawReplayGainReader {
  _FakeReader(this.tags);
  final Map<String, ReplayGainTags?> tags;
  final List<String> reads = <String>[];

  @override
  Future<ReplayGainTags?> read(String path) async {
    reads.add(path);
    return tags[path];
  }
}

TracksCompanion _track(String id, {String? path = '/music/a.mp3'}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album:1',
      artistId: 'artist:1',
      filePath: Value<String?>(path),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  group('Id3Reader.parseReplayGain', () {
    test('reads the four TXXX ReplayGain frames', () {
      final Uint8List bytes = _tag(<(String, List<int>)>[
        ('TXXX', _txxx('replaygain_track_gain', '-7.35 dB')),
        ('TXXX', _txxx('replaygain_track_peak', '0.978210')),
        ('TXXX', _txxx('replaygain_album_gain', '-6.10 dB')),
        ('TXXX', _txxx('replaygain_album_peak', '1.012345')),
      ]);

      final ReplayGainTags tags = Id3Reader.parseReplayGain(bytes);

      expect(tags.trackGainDb, -7.35);
      expect(tags.trackPeak, closeTo(0.978210, 1e-9));
      expect(tags.albumGainDb, -6.10);
      expect(tags.albumPeak, closeTo(1.012345, 1e-9));
    });

    test('descriptions are matched case-insensitively (writers disagree)', () {
      final Uint8List bytes = _tag(<(String, List<int>)>[
        ('TXXX', _txxx('REPLAYGAIN_TRACK_GAIN', '+2.5 dB')),
      ]);
      expect(Id3Reader.parseReplayGain(bytes).trackGainDb, 2.5);
    });

    test('parses a bare number, a comma decimal, and a positive sign', () {
      expect(
        Id3Reader.parseReplayGain(_tag(<(String, List<int>)>[
          ('TXXX', _txxx('replaygain_track_gain', '-3.2')),
        ])).trackGainDb,
        -3.2,
      );
      expect(
        Id3Reader.parseReplayGain(_tag(<(String, List<int>)>[
          ('TXXX', _txxx('replaygain_track_gain', '-3,25 dB')),
        ])).trackGainDb,
        -3.25,
      );
    });

    test('falls back to RVA2 when there is no TXXX gain', () {
      // RVA2: id "track\0", channel 0x01 (master), adjustment -1024 => -2 dB,
      // peak bits 0.
      final List<int> body = <int>[
        ...'track'.codeUnits,
        0,
        0x01,
        0xFC, 0x00, // -1024 as a signed 16-bit => -2.0 dB
        0,
      ];
      final ReplayGainTags tags =
          Id3Reader.parseReplayGain(_tag(<(String, List<int>)>[('RVA2', body)]));
      expect(tags.trackGainDb, closeTo(-2.0, 1e-9));
    });

    test('a TXXX gain wins over RVA2 when a file carries both', () {
      final List<int> rva2 = <int>[
        ...'track'.codeUnits, 0, 0x01, 0xFC, 0x00, 0,
      ];
      final ReplayGainTags tags = Id3Reader.parseReplayGain(
        _tag(<(String, List<int>)>[
          ('RVA2', rva2),
          ('TXXX', _txxx('replaygain_track_gain', '-9.0 dB')),
        ]),
      );
      expect(tags.trackGainDb, -9.0);
    });

    test('an untagged / garbage file yields empty tags, never a throw', () {
      expect(Id3Reader.parseReplayGain(Uint8List(0)).isEmpty, isTrue);
      expect(
        Id3Reader.parseReplayGain(Uint8List.fromList(<int>[1, 2, 3, 4])).isEmpty,
        isTrue,
      );
      // A well-formed tag with unrelated frames.
      expect(
        Id3Reader.parseReplayGain(_tag(<(String, List<int>)>[
          ('TXXX', _txxx('mood', 'sad')),
        ])).isEmpty,
        isTrue,
      );
    });
  });

  group('ReplayGainScanner', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('writes tags and marks each file examined exactly once', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', path: '/music/one.mp3'),
        _track('local:2', path: '/music/two.mp3'),
      ]);
      final _FakeReader reader = _FakeReader(<String, ReplayGainTags?>{
        '/music/one.mp3': const ReplayGainTags(
          trackGainDb: -7.35,
          trackPeak: 0.98,
        ),
        '/music/two.mp3': const ReplayGainTags(), // untagged
      });

      final int tagged =
          await ReplayGainScanner(db.libraryDao, reader: reader).scanPending();

      expect(tagged, 1);
      final List<TrackRow> rows =
          await db.libraryDao.trackRowsByIds(<String>['local:1', 'local:2']);
      final TrackRow one = rows.firstWhere((TrackRow r) => r.id == 'local:1');
      final TrackRow two = rows.firstWhere((TrackRow r) => r.id == 'local:2');
      expect(one.rgTrackGainDb, -7.35);
      expect(one.rgScanned, isTrue);
      expect(two.rgTrackGainDb, isNull);
      // The untagged file is still marked examined — this is what stops it from
      // being re-read on every scan.
      expect(two.rgScanned, isTrue);

      // A second pass reads nothing at all.
      reader.reads.clear();
      final int again =
          await ReplayGainScanner(db.libraryDao, reader: reader).scanPending();
      expect(again, 0);
      expect(reader.reads, isEmpty);
    });

    test('an unreadable file is marked examined, not retried forever', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      final _FakeReader reader =
          _FakeReader(<String, ReplayGainTags?>{'/music/a.mp3': null});

      await ReplayGainScanner(db.libraryDao, reader: reader).scanPending();

      expect(await db.libraryDao.tracksMissingReplayGain(), isEmpty);
    });

    test('reports progress and stops reading when cancelled mid-sweep', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', path: '/a.mp3'),
        _track('local:2', path: '/b.mp3'),
        _track('local:3', path: '/c.mp3'),
      ]);
      final _FakeReader reader = _FakeReader(<String, ReplayGainTags?>{});
      final List<int> progress = <int>[];

      await ReplayGainScanner(db.libraryDao, reader: reader, chunkSize: 1)
          .scanPending(
        // Cancel once the first file has been read: the sweep must abandon the
        // rest rather than plough through the library.
        isCancelled: () => reader.reads.isNotEmpty,
        onProgress: (ReplayGainProgress p) => progress.add(p.processed),
      );

      expect(reader.reads, hasLength(1));
      expect(progress.first, 0); // the initial "found N" tick
      expect(progress.last, 1); // one file examined, then out
      // The examined one is written; the abandoned ones stay pending.
      expect(await db.libraryDao.tracksMissingReplayGain(), hasLength(2));
    });
  });
}
