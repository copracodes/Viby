import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/viby_database.dart';

void main() {
  test('v4 → v5 migration creates eq_settings and eq_presets', () async {
    final Directory dir = await Directory.systemTemp.createTemp('viby_mig5');
    final File file = File('${dir.path}/viby.sqlite');

    // Open at v5, drop the v5 additions, and reset the stored version to v4.
    VibyDatabase db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('SELECT 1'); // open + onCreate
    await db.customStatement('DROP TABLE eq_settings');
    await db.customStatement('DROP TABLE eq_presets');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN visibility');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN user_override');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked');
    await db.customStatement('ALTER TABLE tracks DROP COLUMN liked_at');
    await db.customStatement('PRAGMA user_version = 4');
    await db.close();

    // Reopen: user_version 4 < 5 → onUpgrade recreates both tables. Using the
    // DAO proves the migration ran.
    db = VibyDatabase.forTesting(NativeDatabase(file));
    await db.eqDao.saveSettings(enabled: true, loudnessGain: 6.0);
    final EqSettingsRow? row = await db.eqDao.getSettings();
    expect(row?.enabled, isTrue);
    expect(row?.loudnessGain, 6.0);
    final String id = await db.eqDao.insertCustomPreset('Mine', '{"60":3}');
    expect(await db.eqDao.getCustomPreset(id), isNotNull);
    await db.close();

    await dir.delete(recursive: true);
  });

  group('EqDao settings round-trip', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('defaults are absent until first write', () async {
      expect(await db.eqDao.getSettings(), isNull);
    });

    test('partial upserts leave untouched fields intact', () async {
      await db.eqDao.saveSettings(
        enabled: true,
        loudnessGain: 3.0,
        activePresetId: 'rock',
        bandGainsJson: '{"60":4}',
      );
      // Update only the loudness — everything else must persist.
      await db.eqDao.saveSettings(loudnessGain: 9.0);
      final EqSettingsRow row = (await db.eqDao.getSettings())!;
      expect(row.enabled, isTrue);
      expect(row.loudnessGain, 9.0);
      expect(row.activePresetId, 'rock');
      expect(row.bandGainsJson, '{"60":4}');
    });

    test('activePresetId can be explicitly cleared to null', () async {
      await db.eqDao.saveSettings(activePresetId: 'jazz');
      expect((await db.eqDao.getSettings())!.activePresetId, 'jazz');
      await db.eqDao.saveSettings(activePresetId: null);
      expect((await db.eqDao.getSettings())!.activePresetId, isNull);
    });

    test('watchSettings emits on change', () async {
      await db.eqDao.saveSettings(enabled: true);
      final EqSettingsRow? row = await db.eqDao.watchSettings().first;
      expect(row?.enabled, isTrue);
    });
  });

  group('EqDao custom presets', () {
    late VibyDatabase db;
    setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('insert / rename / delete round-trip', () async {
      final String id = await db.eqDao.insertCustomPreset('Boomy', '{"60":6}');
      expect(id, startsWith('custom:'));

      List<EqPresetRow> rows = await db.eqDao.watchCustomPresets().first;
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Boomy');
      expect(rows.single.gainsJson, '{"60":6}');

      await db.eqDao.renameCustomPreset(id, 'Warm');
      expect((await db.eqDao.getCustomPreset(id))!.name, 'Warm');

      await db.eqDao.deleteCustomPreset(id);
      rows = await db.eqDao.watchCustomPresets().first;
      expect(rows, isEmpty);
      expect(await db.eqDao.getCustomPreset(id), isNull);
    });
  });
}
