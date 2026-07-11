import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

VibyDatabase _db() => VibyDatabase.forTesting(NativeDatabase.memory());

Future<void> _seedTrack(VibyDatabase db, String id) async {
  await db.customStatement(
    "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
    "disc_no, duration_ms, date_added, date_modified, playable) "
    "VALUES ('$id','local','T','a','ar',0,0,1000,0,0,1)",
  );
}

void main() {
  late VibyDatabase db;

  setUp(() async {
    db = _db();
    await _seedTrack(db, 'local:1');
  });

  tearDown(() async => db.close());

  test('upsert then get round-trips all fields', () async {
    final DateTime at = DateTime(2026, 7, 11, 9, 30);
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.embeddedUnsynced,
      synced: false,
      rawText: 'plain lyrics',
      parsedOk: true,
      resolvedAt: at,
    );
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row!.source, LyricsSource.embeddedUnsynced);
    expect(row.synced, isFalse);
    expect(row.rawText, 'plain lyrics');
    expect(row.parsedOk, isTrue);
    expect(row.resolvedAt, at);
  });

  test('upsert replaces in place (idempotent by trackId)', () async {
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
    );
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.sidecarLrc,
      synced: true,
      rawText: '[00:01.00]Hi',
      parsedOk: true,
    );
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row!.source, LyricsSource.sidecarLrc);
    expect(row.synced, isTrue);
  });

  test('watchForTrack emits null then the resolved row', () async {
    final Stream<LyricsRow?> stream = db.lyricsDao.watchForTrack('local:1');
    expect(await stream.first, isNull);
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.sidecarLrc,
      synced: true,
      rawText: '[00:01.00]Hi',
      parsedOk: true,
    );
    final LyricsRow? row =
        await stream.firstWhere((LyricsRow? r) => r != null);
    expect(row!.source, LyricsSource.sidecarLrc);
  });

  test('deleteForTrack / deleteForTracks clear the negative + positive cache',
      () async {
    await _seedTrack(db, 'local:2');
    for (final String id in <String>['local:1', 'local:2']) {
      await db.lyricsDao.upsert(
        trackId: id,
        source: LyricsSource.none,
        synced: false,
        rawText: '',
        parsedOk: false,
      );
    }
    await db.lyricsDao.deleteForTrack('local:1');
    expect(await db.lyricsDao.getForTrack('local:1'), isNull);
    expect(await db.lyricsDao.getForTrack('local:2'), isNotNull);

    await db.lyricsDao.deleteForTracks(<String>['local:2']);
    expect(await db.lyricsDao.getForTrack('local:2'), isNull);
    // Empty input is a no-op (no throw).
    await db.lyricsDao.deleteForTracks(const <String>[]);
  });
}
