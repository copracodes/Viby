import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v2 → v3 migration adds tracks.playable defaulting true', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig3');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at the current (v3) schema, seed one track, then simulate a v2
    // database by dropping the v3 column and resetting the stored version.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // forces open + onCreate
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable) "
      "VALUES ('local:1','local','T','a','ar',0,0,1000,0,0,1)",
    );
    await db.customStatement('ALTER TABLE tracks DROP COLUMN playable');
    // v2 predates the v4 tables too — drop them so onUpgrade recreates them.
    await db.customStatement('DROP TABLE artwork_palettes');
    await db.customStatement('DROP TABLE preferences');
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();

    // Reopen: drift sees user_version 2 < 4 and runs onUpgrade, which must
    // re-add `playable` (and create the v4 tables). The pre-existing row should
    // read back as playable.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    final List<TrackRow> rows = await db.libraryDao.allTrackRows();
    expect(rows.single.playable, isTrue);
    // And the flag is writable post-migration.
    await db.libraryDao.setTrackPlayable('local:1', false);
    final List<TrackRow> after = await db.libraryDao.allTrackRows();
    expect(after.single.playable, isFalse);
    await db.close();

    await dir.delete(recursive: true);
  });
}
