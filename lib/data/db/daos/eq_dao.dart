import 'dart:math';

import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'eq_dao.g.dart';

/// Persistence for the equalizer: the single-row [EqSettings] and the user's
/// custom [EqPresets]. Reads are reactive `watch()` streams so the EQ screen
/// (and any live consumer) reacts to changes; the gain/preset JSON shape lives
/// in `audio/eq_preset.dart` (this DAO stores the strings verbatim).
@DriftAccessor(tables: <Type>[EqSettings, EqPresets])
class EqDao extends DatabaseAccessor<VibyDatabase> with _$EqDaoMixin {
  EqDao(super.db);

  static const int _singletonId = 0;
  final Random _random = Random();

  /// Watches the single settings row (null until first written).
  Stream<EqSettingsRow?> watchSettings() {
    return (select(eqSettings)..where((t) => t.id.equals(_singletonId)))
        .watchSingleOrNull();
  }

  /// One-shot read of the settings row (null until first written).
  Future<EqSettingsRow?> getSettings() {
    return (select(eqSettings)..where((t) => t.id.equals(_singletonId)))
        .getSingleOrNull();
  }

  /// Upserts the settings row. Only the provided fields change: on conflict,
  /// [Value.absent] fields are left untouched; on first insert they fall back to
  /// the column defaults. `activePresetId` uses a sentinel so it can be set to
  /// null explicitly (bespoke curve) vs. left unchanged.
  Future<void> saveSettings({
    bool? enabled,
    double? loudnessGain,
    Object? activePresetId = _unset,
    String? bandGainsJson,
  }) async {
    await into(eqSettings).insertOnConflictUpdate(
      EqSettingsCompanion(
        id: const Value(_singletonId),
        enabled: enabled == null ? const Value.absent() : Value(enabled),
        loudnessGain:
            loudnessGain == null ? const Value.absent() : Value(loudnessGain),
        activePresetId: identical(activePresetId, _unset)
            ? const Value.absent()
            : Value(activePresetId as String?),
        bandGainsJson:
            bandGainsJson == null ? const Value.absent() : Value(bandGainsJson),
      ),
    );
  }

  /// Watches the user's custom presets, newest first.
  Stream<List<EqPresetRow>> watchCustomPresets() {
    return (select(eqPresets)
          ..orderBy(<OrderingTerm Function($EqPresetsTable)>[
            (t) => OrderingTerm.desc(t.dateCreated),
          ]))
        .watch();
  }

  /// One-shot read of a custom preset by id (null if absent). Used on restore
  /// to resolve the active preset's baseline curve.
  Future<EqPresetRow?> getCustomPreset(String id) {
    return (select(eqPresets)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Inserts a custom preset from a pre-encoded frequency→gain JSON string,
  /// returning its minted id.
  Future<String> insertCustomPreset(String name, String gainsJson) async {
    final String id =
        'custom:${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';
    await into(eqPresets).insert(
      EqPresetsCompanion.insert(
        id: id,
        name: name,
        gainsJson: gainsJson,
        dateCreated: DateTime.now(),
      ),
    );
    return id;
  }

  /// Renames a custom preset.
  Future<void> renameCustomPreset(String id, String name) {
    return (update(eqPresets)..where((t) => t.id.equals(id)))
        .write(EqPresetsCompanion(name: Value(name)));
  }

  /// Deletes a custom preset.
  Future<void> deleteCustomPreset(String id) {
    return (delete(eqPresets)..where((t) => t.id.equals(id))).go();
  }

  /// Sentinel distinguishing "don't touch activePresetId" from "set it to null".
  static const Object _unset = Object();
}
