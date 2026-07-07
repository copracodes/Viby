import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/id3_reader.dart';
import 'package:viby/data/sources/local/tag_repair_service.dart';

/// A [RawTagReader] that returns canned tags per file path.
class _FakeReader implements RawTagReader {
  _FakeReader(this.byPath);
  final Map<String, Id3Tags> byPath;
  @override
  Future<Id3Tags?> read(String path) async => byPath[path];
}

TracksCompanion _track(String id, String title, {String? path}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: title,
      albumId: 'al1',
      artistId: 'ar1',
      filePath: Value(path),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  late VibyDatabase db;
  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  // "بحر" is CP1256 [0xC8,0xCD,0xD1]; misdecoded as Latin-1 it is "ÈÍÑ".
  const String arabic = 'بحر';
  const String mojibake = 'ÈÍÑ';

  test('repairs mojibake track titles, album and artist names (no I/O)',
      () async {
    await db.libraryDao.upsertArtists(
      <ArtistsCompanion>[ArtistsCompanion.insert(id: 'ar1', name: mojibake)],
    );
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(id: 'al1', name: mojibake, artistId: 'ar1'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('t1', mojibake),
      _track('t2', 'Clean Title'), // untouched
    ]);

    final RepairResult result = await TagRepairService(db.libraryDao).repairAll();

    expect(result.repaired, 3); // title + album + artist
    final List<TrackRow> tracks = await db.libraryDao.allTrackRows();
    expect(tracks.firstWhere((TrackRow t) => t.id == 't1').title, arabic);
    expect(tracks.firstWhere((TrackRow t) => t.id == 't2').title, 'Clean Title');
    expect((await db.libraryDao.allAlbumRows()).single.name, arabic);
    expect((await db.libraryDao.allArtistRows()).single.name, arabic);
  });

  test('re-reads the file for lossy "????" titles via the tag reader',
      () async {
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('t1', '????', path: '/music/song.mp3'),
    ]);
    // MediaStore lost the bytes to "?", but the raw frame is Latin-1 CP1256.
    final _FakeReader reader = _FakeReader(<String, Id3Tags>{
      '/music/song.mp3': const Id3Tags(title: mojibake),
    });

    await TagRepairService(db.libraryDao, tagReader: reader).repairAll();

    expect((await db.libraryDao.allTrackRows()).single.title, arabic);
  });

  test('is idempotent — a second pass repairs nothing', () async {
    await db.libraryDao.upsertTracks(<TracksCompanion>[_track('t1', mojibake)]);
    await TagRepairService(db.libraryDao).repairAll();
    final RepairResult second =
        await TagRepairService(db.libraryDao).repairAll();
    expect(second.repaired, 0);
  });
}
