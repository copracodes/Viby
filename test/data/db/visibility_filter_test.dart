import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

TracksCompanion _track(
  String id, {
  String title = 'Title',
  TrackVisibility visibility = TrackVisibility.visible,
  bool liked = false,
  DateTime? likedAt,
}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: title,
      albumId: 'album:1',
      artistId: 'artist:1',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
      visibility: Value(visibility),
      liked: Value(liked),
      likedAt: Value(likedAt),
    );

void main() {
  late VibyDatabase db;

  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seed() async {
    await db.libraryDao.upsertArtists(<ArtistsCompanion>[
      ArtistsCompanion.insert(id: 'artist:1', name: 'Artist One'),
    ]);
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(
          id: 'album:1', name: 'Album One', artistId: 'artist:1'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('local:1', title: 'Visible'),
      _track('local:2',
          title: 'HiddenUser', visibility: TrackVisibility.hiddenByUser),
      _track('local:3',
          title: 'HiddenFilter', visibility: TrackVisibility.hiddenByFilter),
    ]);
  }

  group('every track read path excludes hidden rows', () {
    test('searchTracks returns only visible', () async {
      await seed();
      final List<TrackWithMeta> got =
          await db.libraryDao.searchTracks('').first;
      expect(got.map((TrackWithMeta m) => m.track.id).toSet(),
          <String>{'local:1'});
    });

    test('getTracksByIds (queue restore) drops hidden ids', () async {
      await seed();
      final List<TrackWithMeta> got = await db.libraryDao
          .getTracksByIds(<String>['local:1', 'local:2', 'local:3']);
      expect(got.map((TrackWithMeta m) => m.track.id).toSet(),
          <String>{'local:1'});
    });

    test('watchAlbumWithTracks returns only visible', () async {
      await seed();
      final AlbumWithTracks? got =
          await db.libraryDao.watchAlbumWithTracks('album:1').first;
      expect(got, isNotNull);
      expect(got!.tracks.map((TrackRow t) => t.id).toSet(),
          <String>{'local:1'});
    });

    test('watchTrackCount counts only visible; watchHiddenCount the rest',
        () async {
      await seed();
      expect(await db.libraryDao.watchTrackCount().first, 1);
      expect(await db.libraryDao.watchHiddenCount().first, 2);
    });

    test('the two hidden buckets are readable and separated', () async {
      await seed();
      expect(
        (await db.libraryDao.watchHiddenByUser().first)
            .map((TrackWithMeta m) => m.track.id)
            .toSet(),
        <String>{'local:2'},
      );
      expect(
        (await db.libraryDao.watchHiddenByFilter().first)
            .map((TrackWithMeta m) => m.track.id)
            .toSet(),
        <String>{'local:3'},
      );
    });
  });

  group('liked songs', () {
    test('setLiked stamps likedAt; watchLikedTracks orders newest-first',
        () async {
      await seed();
      await db.libraryDao.setLiked('local:1', true, at: DateTime(2026, 1, 1));
      // Like another visible track later.
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:4', title: 'Also visible'),
      ]);
      await db.libraryDao.setLiked('local:4', true, at: DateTime(2026, 2, 2));

      final List<TrackWithMeta> liked =
          await db.libraryDao.watchLikedTracks().first;
      expect(liked.map((TrackWithMeta m) => m.track.id).toList(),
          <String>['local:4', 'local:1']);
      expect(await db.libraryDao.watchLikedCount().first, 2);

      // Unlike clears likedAt and drops it from the collection.
      await db.libraryDao.setLiked('local:4', false);
      final List<TrackWithMeta> after =
          await db.libraryDao.watchLikedTracks().first;
      expect(after.map((TrackWithMeta m) => m.track.id).toList(),
          <String>['local:1']);
    });

    test('a hidden track is never in Liked Songs even if liked', () async {
      await seed();
      await db.libraryDao.setLiked('local:2', true, at: DateTime(2026, 1, 1));
      expect(await db.libraryDao.watchLikedTracks().first, isEmpty);
    });
  });

  group('unhide', () {
    test('setTrackVisibility with userOverride unhides permanently', () async {
      await seed();
      await db.libraryDao.setTrackVisibility('local:3', TrackVisibility.visible,
          userOverride: true);
      final List<TrackWithMeta> visible =
          await db.libraryDao.searchTracks('').first;
      expect(visible.map((TrackWithMeta m) => m.track.id).toSet(),
          <String>{'local:1', 'local:3'});
      final Map<String, ({TrackVisibility visibility, bool userOverride, bool liked, DateTime? likedAt})>
          flags = await db.libraryDao.trackFlags(<String>['local:3']);
      expect(flags['local:3']!.userOverride, isTrue);
    });

    test('unhideAll clears a whole bucket', () async {
      await seed();
      await db.libraryDao.unhideAll(TrackVisibility.hiddenByFilter);
      expect(await db.libraryDao.watchHiddenByFilter().first, isEmpty);
      expect(await db.libraryDao.watchTrackCount().first, 2);
    });
  });
}
