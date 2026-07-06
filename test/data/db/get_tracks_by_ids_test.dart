import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

TracksCompanion _track(String id, {String title = 'Title'}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: title,
      albumId: 'album:1',
      artistId: 'artist:1',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  late VibyDatabase db;

  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('LibraryDao.getTracksByIds', () {
    test('returns only the requested tracks with resolved names', () async {
      await db.libraryDao.upsertArtists(<ArtistsCompanion>[
        ArtistsCompanion.insert(id: 'artist:1', name: 'Artist One'),
      ]);
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        AlbumsCompanion.insert(
          id: 'album:1',
          name: 'Album One',
          artistId: 'artist:1',
        ),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', title: 'One'),
        _track('local:2', title: 'Two'),
        _track('local:3', title: 'Three'),
      ]);

      final List<TrackWithMeta> got =
          await db.libraryDao.getTracksByIds(<String>['local:1', 'local:3']);

      expect(
        got.map((TrackWithMeta m) => m.track.id).toSet(),
        <String>{'local:1', 'local:3'},
      );
      final TrackWithMeta one =
          got.firstWhere((TrackWithMeta m) => m.track.id == 'local:1');
      expect(one.albumName, 'Album One');
      expect(one.artistName, 'Artist One');
    });

    test('ignores ids that do not exist', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      final List<TrackWithMeta> got = await db.libraryDao
          .getTracksByIds(<String>['local:1', 'local:missing']);
      expect(got, hasLength(1));
      expect(got.single.track.id, 'local:1');
    });

    test('empty id list returns empty without hitting the db', () async {
      expect(await db.libraryDao.getTracksByIds(<String>[]), isEmpty);
    });
  });
}
