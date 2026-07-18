import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v8 → v9 migration adds the ReplayGain columns, preserving rows',
      () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig9');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v9, seed a track, then simulate a v8 database by dropping the new
    // columns and resetting the stored version.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // force open + onCreate
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable, liked) "
      "VALUES ('local:1','local','Loud','a','ar',0,0,1000,0,0,1,1)",
    );
    for (final String column in <String>[
      'rg_track_gain_db',
      'rg_track_peak',
      'rg_album_gain_db',
      'rg_album_peak',
      'rg_scanned',
    ]) {
      await db.customStatement('ALTER TABLE tracks DROP COLUMN $column');
    }
    // Schema v10 added lyrics_lines.offset_ms; simulate its absence at v8 so the
    // guarded `if (from >= 7 && from < 10)` addColumn doesn't hit "duplicate
    // column".
    await db.customStatement('ALTER TABLE lyrics_lines DROP COLUMN offset_ms');
    await db.customStatement('PRAGMA user_version = 8');
    await db.close();

    // Reopen: drift runs onUpgrade and adds the columns. The existing row keeps
    // its data, has no gains, and is marked not-yet-examined so the next scan
    // reads its tags.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    final List<TrackRow> rows = await db.libraryDao.trackRowsByIds(<String>['local:1']);
    expect(rows.single.title, 'Loud');
    expect(rows.single.liked, isTrue);
    expect(rows.single.rgTrackGainDb, isNull);
    expect(rows.single.rgScanned, isFalse);

    // The columns are writable post-migration, and the pending query finds it.
    expect(await db.libraryDao.tracksMissingReplayGain(), isEmpty,
        reason: 'no file path, so nothing to read');

    await db.customStatement(
      "UPDATE tracks SET file_path = '/music/loud.mp3' WHERE id = 'local:1'",
    );
    expect((await db.libraryDao.tracksMissingReplayGain()).single.id, 'local:1');

    await db.libraryDao.writeReplayGain(<TrackReplayGain>[
      const TrackReplayGain(
        id: 'local:1',
        trackGainDb: -7.35,
        trackPeak: 0.98,
        albumGainDb: -6.1,
        albumPeak: 1.02,
      ),
    ]);

    final TrackRow after =
        (await db.libraryDao.trackRowsByIds(<String>['local:1'])).single;
    expect(after.rgTrackGainDb, -7.35);
    expect(after.rgTrackPeak, 0.98);
    expect(after.rgAlbumGainDb, -6.1);
    expect(after.rgAlbumPeak, 1.02);
    expect(after.rgScanned, isTrue);
    // Examined once, never re-read.
    expect(await db.libraryDao.tracksMissingReplayGain(), isEmpty);

    // A changed file re-arms the read and clears the stale numbers.
    await db.libraryDao.invalidateReplayGain(<String>['local:1']);
    final TrackRow reset =
        (await db.libraryDao.trackRowsByIds(<String>['local:1'])).single;
    expect(reset.rgScanned, isFalse);
    expect(reset.rgTrackGainDb, isNull);
    expect((await db.libraryDao.tracksMissingReplayGain()).single.id, 'local:1');

    await db.close();
    await dir.delete(recursive: true);
  });
}
