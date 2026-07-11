import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'preferences_dao.g.dart';

/// Reactive key→value store for app preferences (theme mode, dynamic-colour
/// toggle, …). Reads are `watch()` streams so settings-driven UI reacts live.
@DriftAccessor(tables: <Type>[Preferences])
class PreferencesDao extends DatabaseAccessor<VibyDatabase>
    with _$PreferencesDaoMixin {
  PreferencesDao(super.db);

  /// Watches the value for [key] (null until set).
  Stream<String?> watch(String key) {
    return (select(preferences)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((PreferenceRow? row) => row?.value);
  }

  /// One-shot read of [key] (null if unset).
  Future<String?> get(String key) async {
    final PreferenceRow? row =
        await (select(preferences)..where((t) => t.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  /// Sets [key] to [value], overwriting any prior.
  Future<void> set(String key, String value) {
    return into(preferences).insertOnConflictUpdate(
      PreferencesCompanion.insert(key: key, value: value),
    );
  }

  /// Removes [key] (no-op if unset).
  Future<void> remove(String key) {
    return (delete(preferences)..where((t) => t.key.equals(key))).go();
  }
}
