import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/playlist_dao.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

TracksCompanion _track(String id, {String? art}) => TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album:$id',
      artistId: 'artist:1',
      artworkKey: Value<String?>(art),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  group('pickCollageKeys', () {
    test('takes the first four distinct, non-empty keys in order', () {
      expect(
        pickCollageKeys(<String?>['a', 'a', 'b', null, '', 'c', 'd', 'e']),
        <String>['a', 'b', 'c', 'd'],
      );
    });

    test('returns fewer when fewer are available', () {
      expect(pickCollageKeys(<String?>[null, 'x', 'x']), <String>['x']);
    });
  });

  group('PlaylistDao', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('summary collage picks the first four unique album arts', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('t1', art: 'a'),
        _track('t2', art: 'a'), // duplicate art
        _track('t3', art: 'b'),
        _track('t4', art: 'c'),
        _track('t5', art: 'd'),
        _track('t6', art: 'e'), // beyond the fourth unique
      ]);
      final String pid = await db.playlistDao.createPlaylist('Mix');
      await db.playlistDao.addTracks(
        pid,
        <String>['t1', 't2', 't3', 't4', 't5', 't6'],
      );

      final PlaylistSummary summary = (await db.playlistDao
              .watchPlaylistSummaries()
              .first)
          .firstWhere((PlaylistSummary s) => s.playlist.id == pid);

      expect(summary.trackCount, 6);
      expect(summary.artworkKeys, <String>['a', 'b', 'c', 'd']);
    });

    test('toggleTrack adds when absent / removes when present, order dense',
        () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[
        _track('A'),
        _track('B'),
        _track('C'),
        _track('D'),
      ]);
      final String pid = await db.playlistDao.createPlaylist('P');
      await db.playlistDao.addTracks(pid, <String>['A', 'B', 'C']);

      Future<List<String>> order() async {
        final PlaylistWithMeta pwm =
            (await db.playlistDao.watchPlaylistWithMeta(pid).first)!;
        return pwm.tracks.map((m) => m.track.id).toList();
      }

      expect(await db.playlistDao.toggleTrack(pid, 'D'), isTrue); // added
      expect(await order(), <String>['A', 'B', 'C', 'D']);

      expect(await db.playlistDao.toggleTrack(pid, 'B'), isFalse); // removed
      expect(await order(), <String>['A', 'C', 'D']);

      final List<PlaylistEntryRow> entries = await (db.select(db.playlistEntries)
            ..where((t) => t.playlistId.equals(pid))
            ..orderBy(<OrderClauseGenerator<$PlaylistEntriesTable>>[
              (t) => OrderingTerm(expression: t.position),
            ]))
          .get();
      expect(entries.map((PlaylistEntryRow e) => e.position).toList(),
          <int>[0, 1, 2]);
    });

    test('containment stream reflects add / remove', () async {
      await db.libraryDao.upsertTracks(<TracksCompanion>[_track('X')]);
      final String pid = await db.playlistDao.createPlaylist('P');
      expect(
        await db.playlistDao.watchPlaylistIdsContaining('X').first,
        isEmpty,
      );
      await db.playlistDao.toggleTrack(pid, 'X');
      expect(
        await db.playlistDao.watchPlaylistIdsContaining('X').first,
        <String>{pid},
      );
    });
  });
}
