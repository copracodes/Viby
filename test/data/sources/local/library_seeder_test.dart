import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/library_seeder.dart';

void main() {
  late VibyDatabase db;
  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds the requested counts under the synthetic marker prefix',
      () async {
    await LibrarySeeder(db.libraryDao)
        .seed(tracks: 200, albums: 20, artists: 10, chunkSize: 64);

    expect(await db.libraryDao.trackCount(), 200);
    expect((await db.libraryDao.allAlbumRows()).length, 20);
    expect((await db.libraryDao.allArtistRows()).length, 10);
    expect(
      (await db.libraryDao.allTrackRows())
          .every((TrackRow t) => t.id.startsWith(kSyntheticPrefix)),
      isTrue,
    );
  });

  test('clear removes only synthetic rows, never real ones', () async {
    final LibrarySeeder seeder = LibrarySeeder(db.libraryDao);
    await seeder.seed(tracks: 50, albums: 5, artists: 3);
    // A real (non-synthetic) track that must survive the clear.
    await db.libraryDao.upsertArtists(
      <ArtistsCompanion>[ArtistsCompanion.insert(id: 'local:artist:9', name: 'Real')],
    );
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(id: 'local:album:9', name: 'Real', artistId: 'local:artist:9'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      TracksCompanion.insert(
        id: 'local:99',
        source: TrackSource.local,
        title: 'Real Song',
        albumId: 'local:album:9',
        artistId: 'local:artist:9',
        dateAdded: DateTime(2026),
        dateModified: DateTime(2026),
      ),
    ]);

    final int removed = await seeder.clear();

    expect(removed, 50);
    final List<TrackRow> remaining = await db.libraryDao.allTrackRows();
    expect(remaining.map((TrackRow t) => t.id), <String>['local:99']);
  });
}
