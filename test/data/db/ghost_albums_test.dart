import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

/// A junk recording ("Alarms", "Call") is stored *hidden*, not dropped — so its
/// album/artist rows outlive it. These tests pin that such rows never surface in
/// the library as empty ghost cards, while the Hidden-songs screen still resolves
/// their names.

TracksCompanion _track(
  String id, {
  required String album,
  required String artist,
  TrackVisibility visibility = TrackVisibility.visible,
}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: album,
      artistId: artist,
      visibility: Value(visibility),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  late VibyDatabase db;

  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// A real album ("Greatest" by The Band) and a junk one ("Alarms" by Unknown)
  /// whose only track was auto-hidden by the junk filter.
  Future<void> seedRealAndGhost() async {
    await db.libraryDao.upsertArtists(<ArtistsCompanion>[
      ArtistsCompanion.insert(id: 'artist:band', name: 'The Band'),
      ArtistsCompanion.insert(id: 'artist:unknown', name: 'Unknown artist'),
    ]);
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(
          id: 'album:greatest', name: 'Greatest', artistId: 'artist:band'),
      AlbumsCompanion.insert(
          id: 'album:alarms', name: 'Alarms', artistId: 'artist:unknown'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('local:1', album: 'album:greatest', artist: 'artist:band'),
      _track('local:2', album: 'album:greatest', artist: 'artist:band'),
      _track(
        'local:99',
        album: 'album:alarms',
        artist: 'artist:unknown',
        visibility: TrackVisibility.hiddenByFilter,
      ),
    ]);
    await db.libraryDao.recomputeAllAlbumTrackCounts();
  }

  group('ghost albums / artists never reach the library', () {
    test('an album whose only track is hidden is not in the grid', () async {
      await seedRealAndGhost();

      final List<AlbumWithArtist> grid =
          await db.libraryDao.watchAlbumsWithArtist().first;

      expect(grid.map((AlbumWithArtist a) => a.album.name), <String>['Greatest']);
      expect(await db.libraryDao.watchAllAlbums().first, hasLength(1));
    });

    test('an artist with only ghost albums is not in the artists list',
        () async {
      await seedRealAndGhost();

      final List<ArtistRow> artists = await db.libraryDao.watchAllArtists().first;

      expect(artists.map((ArtistRow a) => a.name), <String>['The Band']);
    });

    test('artist detail lists only their non-ghost albums', () async {
      await db.libraryDao.upsertArtists(<ArtistsCompanion>[
        ArtistsCompanion.insert(id: 'artist:band', name: 'The Band'),
      ]);
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        AlbumsCompanion.insert(
            id: 'album:real', name: 'Real', artistId: 'artist:band'),
        AlbumsCompanion.insert(
            id: 'album:ghost', name: 'Ghost', artistId: 'artist:band'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', album: 'album:real', artist: 'artist:band'),
        _track('local:2',
            album: 'album:ghost',
            artist: 'artist:band',
            visibility: TrackVisibility.hiddenByUser),
      ]);

      final ArtistWithAlbums? detail =
          await db.libraryDao.watchArtistWithAlbums('artist:band').first;

      expect(detail!.albums.map((AlbumRow a) => a.name), <String>['Real']);
    });

    test('trackCount counts visible tracks only', () async {
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        AlbumsCompanion.insert(
            id: 'album:mixed', name: 'Mixed', artistId: 'artist:band'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', album: 'album:mixed', artist: 'artist:band'),
        _track('local:2', album: 'album:mixed', artist: 'artist:band'),
        _track('local:3',
            album: 'album:mixed',
            artist: 'artist:band',
            visibility: TrackVisibility.hiddenByFilter),
      ]);

      await db.libraryDao.recomputeAlbumTrackCounts(<String>{'album:mixed'});

      final List<AlbumRow> albums = await db.libraryDao.watchAllAlbums().first;
      // The card's number matches the list you get when you open it.
      expect(albums.single.trackCount, 2);
    });
  });

  group('hide / unhide round-trip is live', () {
    test('hiding the last visible track makes its album vanish, unhiding brings '
        'it back', () async {
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        AlbumsCompanion.insert(
            id: 'album:solo', name: 'Solo', artistId: 'artist:band'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', album: 'album:solo', artist: 'artist:band'),
      ]);

      // Watch the grid the way the UI does, and drive hide/unhide underneath it.
      final List<int> seen = <int>[];
      final StreamSubscription<List<AlbumRow>> sub = db.libraryDao
          .watchAllAlbums()
          .listen((List<AlbumRow> rows) => seen.add(rows.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, <int>[1]);

      await db.libraryDao
          .setTrackVisibility('local:1', TrackVisibility.hiddenByUser);
      await pumpEventQueue();
      expect(seen.last, 0, reason: 'the album vanishes live when hidden');
      // The count drops with it (visible-only).
      expect(
        (await (db.select(db.albums)
                  ..where(($AlbumsTable a) => a.id.equals('album:solo')))
                .getSingle())
            .trackCount,
        0,
      );

      await db.libraryDao.setTrackVisibility(
        'local:1',
        TrackVisibility.visible,
        userOverride: true,
      );
      await pumpEventQueue();
      expect(seen.last, 1, reason: 'and comes back live when unhidden');
      expect(
        (await (db.select(db.albums)
                  ..where(($AlbumsTable a) => a.id.equals('album:solo')))
                .getSingle())
            .trackCount,
        1,
      );
    });

    test('unhide-all restores the artist too', () async {
      await seedRealAndGhost();
      expect(await db.libraryDao.watchAllArtists().first, hasLength(1));

      await db.libraryDao.unhideAll(TrackVisibility.hiddenByFilter);

      expect(await db.libraryDao.watchAllArtists().first, hasLength(2));
      expect(await db.libraryDao.watchAllAlbums().first, hasLength(2));
    });
  });

  group('the Hidden-songs screen is NOT filtered', () {
    test('hidden tracks still resolve their album + artist names', () async {
      await seedRealAndGhost();

      final List<TrackWithMeta> hidden =
          await db.libraryDao.watchHiddenByFilter().first;

      expect(hidden, hasLength(1));
      expect(hidden.single.track.id, 'local:99');
      // The ghost rows survive precisely so these names can be shown.
      expect(hidden.single.albumName, 'Alarms');
      expect(hidden.single.artistName, 'Unknown artist');
      // ...and the single-artist lookup (headers) stays unfiltered too.
      expect(
        (await db.libraryDao.watchArtist('artist:unknown').first)?.name,
        'Unknown artist',
      );
    });
  });
}
