import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v3 → v4 migration creates artwork_palettes and preferences', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig4');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v4, drop the v4 additions, and reset the stored version to v3.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // open + onCreate
    await db.customStatement('DROP TABLE artwork_palettes');
    await db.customStatement('DROP TABLE preferences');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN visibility');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN user_override');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked_at');
    await db.customStatement('PRAGMA user_version = 3');
    await db.close();

    // Reopen: user_version 3 < 4 → onUpgrade recreates both tables. Using the
    // DAOs proves the migration ran.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.paletteDao.putSeed('local:album:1', 0xFF7C4DFF);
    expect(await db.paletteDao.getSeed('local:album:1'), 0xFF7C4DFF);
    await db.preferencesDao.set('theme_mode', 'amoled');
    expect(await db.preferencesDao.get('theme_mode'), 'amoled');
    await db.close();

    await dir.delete(recursive: true);
  });

  group('PaletteDao', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('putSeed upserts and getSeed reads back (null when absent)', () async {
      expect(await db.paletteDao.getSeed('nope'), isNull);
      await db.paletteDao.putSeed('k', 0x11223344);
      expect(await db.paletteDao.getSeed('k'), 0x11223344);
      await db.paletteDao.putSeed('k', 0x55667788); // overwrite
      expect(await db.paletteDao.getSeed('k'), 0x55667788);
    });
  });

  group('PreferencesDao', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('set/get/watch round-trip', () async {
      expect(await db.preferencesDao.get('dynamic_color'), isNull);
      await db.preferencesDao.set('dynamic_color', '1');
      expect(await db.preferencesDao.get('dynamic_color'), '1');
      expect(await db.preferencesDao.watch('dynamic_color').first, '1');
    });
  });
}
