import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v6 → v7 migration creates the lyrics table (cascades on track delete)',
      () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig7');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v7, seed a track, then simulate a v6 database by dropping the new
    // table and resetting the stored version.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // forces open + onCreate
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable) "
      "VALUES ('local:1','local','T','a','ar',0,0,1000,0,0,1)",
    );
    await db.customStatement('DROP TABLE lyrics_lines');
    await db.customStatement('PRAGMA user_version = 6');
    await db.close();

    // Reopen: drift sees user_version 6 < 7 and runs onUpgrade, creating the
    // table. It must be writable and readable post-migration.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.sidecarLrc,
      synced: true,
      rawText: '[00:01.00]Hi',
      parsedOk: true,
      resolvedAt: DateTime(2026, 7, 11),
    );
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row, isNotNull);
    expect(row!.source, LyricsSource.sidecarLrc);
    expect(row.synced, isTrue);

    // Cascade: deleting the track removes its lyrics row (FK ON DELETE CASCADE).
    await db.customStatement("DELETE FROM tracks WHERE id = 'local:1'");
    expect(await db.lyricsDao.getForTrack('local:1'), isNull);
    await db.close();

    await dir.delete(recursive: true);
  });
}
