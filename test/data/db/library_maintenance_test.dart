import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/artwork_service.dart';
import 'package:viby/data/sources/local/library_maintenance.dart';

/// Records evictions instead of touching the filesystem.
class _FakeEvictor implements ArtworkEvictor {
  final List<String> evicted = <String>[];

  @override
  Future<void> evictArtwork(String artworkKey) async => evicted.add(artworkKey);
}

/// An evictor whose file delete always blows up (a stuck/locked art file).
class _ThrowingEvictor implements ArtworkEvictor {
  @override
  Future<void> evictArtwork(String artworkKey) async =>
      throw const FileSystemException('locked');
}

TracksCompanion _track(
  String id, {
  String album = 'local:album:1',
  String artist = 'local:artist:1',
  String? art = 'local:album:1',
}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: album,
      artistId: artist,
      artworkKey: Value<String?>(art),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

AlbumsCompanion _album(
  String id, {
  String artist = 'local:artist:1',
  String? art,
}) =>
    AlbumsCompanion.insert(
      id: id,
      name: id,
      artistId: artist,
      artworkKey: Value<String?>(art ?? id),
    );

void main() {
  late VibyDatabase db;
  late _FakeEvictor evictor;
  late LibraryMaintenance maintenance;

  setUp(() {
    db = VibyDatabase.forTesting(NativeDatabase.memory());
    evictor = _FakeEvictor();
    maintenance = LibraryMaintenance(db, artwork: evictor);
  });
  tearDown(() async => db.close());

  group('purgeTracks cascade', () {
    test('removes the track and everything hanging off it', () async {
      await db.libraryDao.upsertArtists(<ArtistsCompanion>[
        ArtistsCompanion.insert(id: 'local:artist:1', name: 'A'),
      ]);
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        _album('local:album:1'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      await db.historyDao
          .recordPlay(trackId: 'local:1', playedAt: DateTime(2026));
      await db.lyricsDao.upsert(
        trackId: 'local:1',
        source: LyricsSource.online,
        rawText: '[00:01.00] hi',
        synced: true,
        parsedOk: true,
      );

      final PurgeResult result =
          await maintenance.purgeTracks(<String>['local:1']);

      expect(result.tracks, 1);
      expect(await db.libraryDao.trackCount(), 0);
      // FK cascades: history + lyrics die with the row.
      expect(await db.lyricsDao.getForTrack('local:1'), isNull);
      expect(
        await db.historyDao.watchRecentlyPlayed(limit: 10).first,
        isEmpty,
      );
    });

    test('drops playlist entries and re-compacts the remaining positions',
        () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1'),
        _track('local:2'),
        _track('local:3'),
      ]);
      final String playlistId = await db.playlistDao.createPlaylist('Mix');
      await db.playlistDao.addTracks(
        playlistId,
        <String>['local:1', 'local:2', 'local:3'],
      );

      await maintenance.purgeTracks(<String>['local:2']);

      final List<PlaylistEntryRow> entries =
          await db.select(db.playlistEntries).get();
      expect(entries.map((PlaylistEntryRow e) => e.trackId),
          <String>['local:1', 'local:3']);
      // Dense 0..n-1 — no hole where local:2 used to be.
      expect(entries.map((PlaylistEntryRow e) => e.position).toList()..sort(),
          <int>[0, 1]);
    });

    test('deletes an album (and its artist) once its last track dies', () async {
      await db.libraryDao.upsertArtists(<ArtistsCompanion>[
        ArtistsCompanion.insert(id: 'local:artist:1', name: 'A'),
      ]);
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        _album('local:album:1'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1'),
        _track('local:2'),
      ]);

      // First of two: album survives, count drops to 1.
      final PurgeResult first =
          await maintenance.purgeTracks(<String>['local:1']);
      expect(first.albums, isEmpty);
      final List<AlbumRow> albums =
          await db.libraryDao.watchAllAlbums().first;
      expect(albums.single.trackCount, 1);

      // Last one: the album and the now-artist-less artist go too.
      final PurgeResult second =
          await maintenance.purgeTracks(<String>['local:2']);
      expect(second.albums, <String>{'local:album:1'});
      expect(second.artists, <String>{'local:artist:1'});
      expect(await db.libraryDao.watchAllAlbums().first, isEmpty);
      expect(await db.libraryDao.watchAllArtists().first, isEmpty);
    });

    test('evicts orphaned artwork (file + cached palette), keeps art still used',
        () async {
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        _album('local:album:1'),
        _album('local:album:2'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1'),
        _track('local:2',
            album: 'local:album:2', art: 'local:album:2'),
        _track('local:3',
            album: 'local:album:2', art: 'local:album:2'),
      ]);
      await db.paletteDao.putSeed('local:album:1', 0xFF00FF00);
      await db.paletteDao.putSeed('local:album:2', 0xFF0000FF);

      // album:1 loses its only track; album:2 keeps one.
      final PurgeResult result =
          await maintenance.purgeTracks(<String>['local:1', 'local:2']);

      expect(result.artworkKeys, <String>{'local:album:1'});
      expect(evictor.evicted, <String>['local:album:1']);
      expect(await db.paletteDao.getSeed('local:album:1'), isNull);
      // album:2's art is still on a surviving track — untouched.
      expect(await db.paletteDao.getSeed('local:album:2'), 0xFF0000FF);
    });

    test('a failed artwork eviction never fails the purge', () async {
      final LibraryMaintenance stubborn =
          LibraryMaintenance(db, artwork: _ThrowingEvictor());
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        _album('local:album:1'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);

      final PurgeResult result =
          await stubborn.purgeTracks(<String>['local:1']);

      expect(result.tracks, 1);
      expect(await db.libraryDao.trackCount(), 0);
    });

    test('purges hidden tracks too (visibility never shields a row)', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      await db.libraryDao
          .setTrackVisibility('local:1', TrackVisibility.hiddenByUser);

      expect((await maintenance.purgeTracks(<String>['local:1'])).tracks, 1);
      expect(await db.libraryDao.trackCount(), 0);
    });
  });

  group('idempotency (the observer rescan races the purge)', () {
    test('purging ids that are already gone is a no-op', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      final String playlistId = await db.playlistDao.createPlaylist('Mix');
      await db.playlistDao.addTracks(playlistId, <String>['local:1']);

      final PurgeResult first =
          await maintenance.purgeTracks(<String>['local:1']);
      final PurgeResult second =
          await maintenance.purgeTracks(<String>['local:1']);

      expect(first.tracks, 1);
      expect(second.tracks, 0);
      expect(second.isEmpty, isTrue);
      // The second pass evicted nothing extra and left no residue.
      expect(evictor.evicted.length, 1);
      expect(await db.select(db.playlistEntries).get(), isEmpty);
    });

    test('two purges of the same id running concurrently delete it once',
        () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1'),
        _track('local:2'),
      ]);

      // The scanner's deletion path and a user delete, firing together.
      final List<PurgeResult> results = await Future.wait(<Future<PurgeResult>>[
        maintenance.purgeTracks(<String>['local:1']),
        maintenance.purgeTracks(<String>['local:1']),
      ]);

      expect(results.map((PurgeResult r) => r.tracks).toList()..sort(),
          <int>[0, 1]);
      expect(await db.libraryDao.trackCount(), 1); // local:2 untouched
    });

    test('an empty id list does nothing', () async {
      expect((await maintenance.purgeTracks(<String>[])).isEmpty, isTrue);
    });
  });
}
