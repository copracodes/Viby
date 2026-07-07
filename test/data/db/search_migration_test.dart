import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v1 → v2 migration creates the searches table', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at the current schema, then simulate a v1 database by undoing every
    // later addition (the v2 searches table AND the v3 playable column) and
    // resetting the stored schema version, so onUpgrade replays 1 → 3 cleanly.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // forces open + onCreate
    await db.customStatement('DROP TABLE searches');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN playable');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    // Reopen: drift sees user_version 1 < 3 and runs onUpgrade, which must
    // recreate `searches` and re-add `playable`. Using both proves it ran.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.searchDao.recordSearch('daft punk');
    final List<String> recents = await db.searchDao.watchRecentSearches().first;
    expect(recents, contains('daft punk'));
    await db.close();

    await dir.delete(recursive: true);
  });

  group('SearchDao', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('keeps only the newest 10, newest first, and prunes the rest',
        () async {
      for (int i = 0; i < 12; i++) {
        await db.searchDao.recordSearch('q$i', at: DateTime(2026, 1, 1, 0, 0, i));
      }
      final List<String> recents =
          await db.searchDao.watchRecentSearches().first;
      expect(recents, hasLength(10));
      expect(recents.first, 'q11');
      expect(recents.contains('q0'), isFalse);
      expect(recents.contains('q1'), isFalse);
    });

    test('re-searching an existing term refreshes it to the top', () async {
      await db.searchDao.recordSearch('alpha', at: DateTime(2026, 1, 1, 0, 0, 1));
      await db.searchDao.recordSearch('beta', at: DateTime(2026, 1, 1, 0, 0, 2));
      await db.searchDao.recordSearch('alpha', at: DateTime(2026, 1, 1, 0, 0, 3));
      final List<String> recents =
          await db.searchDao.watchRecentSearches().first;
      expect(recents, <String>['alpha', 'beta']);
    });

    test('clear removes everything; blank queries are ignored', () async {
      await db.searchDao.recordSearch('  ');
      expect(await db.searchDao.watchRecentSearches().first, isEmpty);
      await db.searchDao.recordSearch('jazz');
      await db.searchDao.clearSearches();
      expect(await db.searchDao.watchRecentSearches().first, isEmpty);
    });
  });
}
