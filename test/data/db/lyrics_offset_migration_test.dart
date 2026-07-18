import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v9 → v10 migration adds lyrics_lines.offset_ms (default 0)', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig10');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v10, seed a track + lyrics row, then simulate a v9 database by
    // dropping the new column and resetting the stored version.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // force open + onCreate
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable) "
      "VALUES ('local:1','local','T','a','ar',0,0,1000,0,0,1)",
    );
    await db.customStatement(
      "INSERT INTO lyrics_lines (track_id, source, synced, raw_text, "
      "parsed_ok, resolved_at) VALUES ('local:1','sidecarLrc',1,'[00:01.00]Hi',1,0)",
    );
    await db.customStatement('ALTER TABLE lyrics_lines DROP COLUMN offset_ms');
    await db.customStatement('PRAGMA user_version = 9');
    await db.close();

    // Reopen: drift sees user_version 9 < 10 and runs onUpgrade, adding the
    // column with its default. The pre-existing row keeps its data at offset 0.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    LyricsRow? row = await db.lyricsDao.getForTrack('local:1');
    expect(row, isNotNull);
    expect(row!.source, LyricsSource.sidecarLrc);
    expect(row.offsetMs, 0);

    // Round-trip: setOffset persists and watchOffset reflects it.
    await db.lyricsDao.setOffset('local:1', 1500);
    expect(await db.lyricsDao.watchOffset('local:1').first, 1500);

    // Reset.
    await db.lyricsDao.setOffset('local:1', 0);
    expect(await db.lyricsDao.watchOffset('local:1').first, 0);

    // A re-resolve (upsert) must PRESERVE a user offset, not reset it.
    await db.lyricsDao.setOffset('local:1', -800);
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.online,
      synced: true,
      rawText: '[00:02.00]New',
      parsedOk: true,
      resolvedAt: DateTime(2026, 7, 18),
    );
    row = await db.lyricsDao.getForTrack('local:1');
    expect(row!.source, LyricsSource.online, reason: 're-resolve updated source');
    expect(row.offsetMs, -800, reason: 'offset survives re-resolution');

    await db.close();
    await dir.delete(recursive: true);
  });
}
