import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/daos/queue_dao.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

TracksCompanion _track(
  String id, {
  String title = 'Title',
  String albumId = 'album:1',
  String artistId = 'artist:1',
}) {
  return TracksCompanion.insert(
    id: id,
    source: TrackSource.local,
    title: title,
    albumId: albumId,
    artistId: artistId,
    dateAdded: DateTime(2026),
    dateModified: DateTime(2026),
  );
}

Future<List<String>> _entryOrder(VibyDatabase db, String playlistId) async {
  final List<PlaylistEntryRow> entries = await (db.select(db.playlistEntries)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy(<OrderClauseGenerator<$PlaylistEntriesTable>>[
          (t) => OrderingTerm(expression: t.position),
        ]))
      .get();
  return entries.map((PlaylistEntryRow e) => e.trackId).toList();
}

Future<List<int>> _positions(VibyDatabase db, String playlistId) async {
  final List<PlaylistEntryRow> entries = await (db.select(db.playlistEntries)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy(<OrderClauseGenerator<$PlaylistEntriesTable>>[
          (t) => OrderingTerm(expression: t.position),
        ]))
      .get();
  return entries.map((PlaylistEntryRow e) => e.position).toList();
}

void main() {
  late VibyDatabase db;

  setUp(() {
    db = VibyDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  group('LibraryDao upsert', () {
    test('is idempotent by id and updates fields on re-scan', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', title: 'First'),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', title: 'Second'),
      ]);

      final List<TrackRow> all =
          await db.libraryDao.watchAllTracks(TrackSortOrder.titleAsc).first;
      expect(all, hasLength(1));
      expect(all.single.title, 'Second');
    });
  });

  group('LibraryDao search', () {
    setUp(() async {
      await db.libraryDao.upsertArtists(<ArtistsCompanion>[
        ArtistsCompanion.insert(id: 'artist:1', name: 'The Beatles'),
      ]);
      await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
        AlbumsCompanion.insert(
          id: 'album:1',
          name: 'Abbey Road',
          artistId: 'artist:1',
        ),
      ]);
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('local:1', title: 'Come Together'),
        _track(
          'local:2',
          title: 'Yesterday',
          albumId: 'album:2',
          artistId: 'artist:2',
        ),
      ]);
    });

    Future<List<String>> ids(String query) async {
      final List<TrackWithMeta> results =
          await db.libraryDao.searchTracks(query).first;
      return results.map((TrackWithMeta r) => r.track.id).toList();
    }

    test('matches on track title (case-insensitive)', () async {
      expect(await ids('come'), <String>['local:1']);
      expect(await ids('COME together'), <String>['local:1']);
    });

    test('matches on album name (case-insensitive)', () async {
      expect(await ids('ABBEY'), <String>['local:1']);
    });

    test('matches on artist name (case-insensitive)', () async {
      expect(await ids('beatles'), <String>['local:1']);
    });

    test('returns empty on no match', () async {
      expect(await ids('nonexistent'), isEmpty);
    });
  });

  group('PlaylistDao reorder', () {
    late String pid;
    setUp(() async {
      pid = await db.playlistDao.createPlaylist('P');
      await db.playlistDao.addTracks(pid, <String>['t0', 't1', 't2', 't3']);
    });

    test('appends with dense positions', () async {
      expect(await _entryOrder(db, pid), <String>['t0', 't1', 't2', 't3']);
      expect(await _positions(db, pid), <int>[0, 1, 2, 3]);
    });

    test('move down keeps order and dense positions', () async {
      await db.playlistDao.reorderEntry(playlistId: pid, from: 0, to: 2);
      expect(await _entryOrder(db, pid), <String>['t1', 't2', 't0', 't3']);
      expect(await _positions(db, pid), <int>[0, 1, 2, 3]);
    });

    test('move up keeps order and dense positions', () async {
      await db.playlistDao.reorderEntry(playlistId: pid, from: 3, to: 0);
      expect(await _entryOrder(db, pid), <String>['t3', 't0', 't1', 't2']);
      expect(await _positions(db, pid), <int>[0, 1, 2, 3]);
    });

    test('removeEntry re-compacts positions', () async {
      await db.playlistDao.removeEntry(playlistId: pid, position: 1);
      expect(await _entryOrder(db, pid), <String>['t0', 't2', 't3']);
      expect(await _positions(db, pid), <int>[0, 1, 2]);
    });
  });

  group('cascade deletes', () {
    test('deleting a playlist removes its entries', () async {
      final String pid = await db.playlistDao.createPlaylist('P');
      await db.playlistDao.addTracks(pid, <String>['t0', 't1']);
      expect(await db.select(db.playlistEntries).get(), isNotEmpty);

      await db.playlistDao.deletePlaylist(pid);
      expect(await db.select(db.playlistEntries).get(), isEmpty);
    });

    test('deleting a track removes its play history', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      await db.historyDao.recordPlay(trackId: 'local:1');
      expect(await db.select(db.playHistory).get(), isNotEmpty);

      await db.libraryDao.deleteTrack('local:1');
      expect(await db.select(db.playHistory).get(), isEmpty);
    });

    test('deleting a track removes its cache entry', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('local:1')]);
      await db.cacheDao.upsertCacheEntry(
        CacheEntriesCompanion.insert(
          trackId: 'local:1',
          path: '/1',
          state: CacheState.complete,
          lastAccessed: DateTime(2026),
        ),
      );
      expect(await db.select(db.cacheEntries).get(), isNotEmpty);

      await db.libraryDao.deleteTrack('local:1');
      expect(await db.select(db.cacheEntries).get(), isEmpty);
    });
  });

  group('CacheDao eviction', () {
    test('evictionCandidates excludes pinned, oldest access first', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('t1'),
        _track('t2'),
        _track('t3'),
      ]);
      await db.cacheDao.upsertCacheEntry(
        CacheEntriesCompanion.insert(
          trackId: 't1',
          path: '/1',
          state: CacheState.complete,
          lastAccessed: DateTime(2026, 1, 1),
          pinned: const Value(true),
        ),
      );
      await db.cacheDao.upsertCacheEntry(
        CacheEntriesCompanion.insert(
          trackId: 't2',
          path: '/2',
          state: CacheState.complete,
          lastAccessed: DateTime(2026, 1, 3),
        ),
      );
      await db.cacheDao.upsertCacheEntry(
        CacheEntriesCompanion.insert(
          trackId: 't3',
          path: '/3',
          state: CacheState.complete,
          lastAccessed: DateTime(2026, 1, 2),
        ),
      );

      final List<CacheEntryRow> candidates =
          await db.cacheDao.evictionCandidates();
      expect(candidates.every((CacheEntryRow c) => !c.pinned), isTrue);
      // t2 (older-access after t3? t3=Jan2 < t2=Jan3) → t3 then t2.
      expect(
        candidates.map((CacheEntryRow c) => c.trackId),
        <String>['t3', 't2'],
      );
    });
  });

  group('QueueDao', () {
    test('round-trips a snapshot and stays single-row', () async {
      await db.queueDao.saveQueueState(
        const QueueSnapshot(
          trackIds: <String>['a', 'b', 'c'],
          currentIndex: 1,
          positionMs: 42000,
          shuffleOn: true,
          repeatMode: RepeatMode.all,
        ),
      );

      final QueueSnapshot? loaded = await db.queueDao.loadQueueState();
      expect(loaded, isNotNull);
      expect(loaded!.trackIds, <String>['a', 'b', 'c']);
      expect(loaded.currentIndex, 1);
      expect(loaded.positionMs, 42000);
      expect(loaded.shuffleOn, isTrue);
      expect(loaded.repeatMode, RepeatMode.all);

      await db.queueDao.saveQueueState(
        const QueueSnapshot(
          trackIds: <String>['x'],
          currentIndex: 0,
          positionMs: 0,
          shuffleOn: false,
          repeatMode: RepeatMode.off,
        ),
      );
      expect(await db.select(db.queueState).get(), hasLength(1));
    });
  });
}
