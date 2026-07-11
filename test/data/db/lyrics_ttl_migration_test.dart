import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v7 → v8 migration adds lyrics_lines.expires_at (nullable)', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig8');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v8, seed a track + lyrics row, then simulate a v7 database by
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
      "parsed_ok, resolved_at) VALUES ('local:1','online',1,'[00:01.00]Hi',1,0)",
    );
    await db.customStatement('ALTER TABLE lyrics_lines DROP COLUMN expires_at');
    await db.customStatement('PRAGMA user_version = 7');
    await db.close();

    // Reopen: drift sees user_version 7 < 8 and runs onUpgrade, adding the
    // nullable column. The pre-existing row keeps its data; expiresAt is null.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row, isNotNull);
    expect(row!.source, LyricsSource.online);
    expect(row.expiresAt, isNull);

    // The new column is writable post-migration.
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
      resolvedAt: DateTime(2026, 7, 11),
      expiresAt: DateTime(2026, 7, 25),
    );
    final after = await db.lyricsDao.getForTrack('local:1');
    expect(after!.expiresAt, DateTime(2026, 7, 25));
    await db.close();

    await dir.delete(recursive: true);
  });
}
