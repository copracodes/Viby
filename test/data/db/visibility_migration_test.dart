import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test(
      'v5 → v6 migration adds visibility/userOverride/liked/likedAt with '
      'sensible defaults', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig6');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at the current (v6) schema, seed one track, then simulate a v5
    // database by dropping the v6 columns and resetting the stored version.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // forces open + onCreate
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable) "
      "VALUES ('local:1','local','T','a','ar',0,0,1000,0,0,1)",
    );
    await db.customStatement('ALTER TABLE tracks DROP COLUMN visibility');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN user_override');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked_at');
    await db.customStatement('PRAGMA user_version = 5');
    await db.close();

    // Reopen: drift sees user_version 5 < 6 and runs onUpgrade, which must
    // add the four columns. The pre-existing row defaults to visible / not
    // overridden / not liked — nothing changes until the next scan re-scores.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    final List<TrackRow> rows = await db.libraryDao.allTrackRows();
    expect(rows.single.visibility, TrackVisibility.visible);
    expect(rows.single.userOverride, isFalse);
    expect(rows.single.liked, isFalse);
    expect(rows.single.likedAt, isNull);

    // And the new columns are writable post-migration.
    await db.libraryDao.setLiked('local:1', true, at: DateTime(2026, 5, 6));
    await db.libraryDao
        .setTrackVisibility('local:1', TrackVisibility.hiddenByUser);
    final List<TrackRow> after = await db.libraryDao.allTrackRows();
    expect(after.single.liked, isTrue);
    expect(after.single.likedAt, DateTime(2026, 5, 6));
    expect(after.single.visibility, TrackVisibility.hiddenByUser);
    await db.close();

    await dir.delete(recursive: true);
  });
}
