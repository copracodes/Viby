import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/state/database_providers.dart';
import 'package:viby/state/theme_providers.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 60));

/// Builds a container over an in-memory db. tearDowns run LIFO, so the container
/// is disposed before the db closes; callers still [_settle] to let the
/// notifier's async hydration complete before the db goes away.
(ProviderContainer, VibyDatabase) _setup() {
  final VibyDatabase db = VibyDatabase.forTesting(NativeDatabase.memory());
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[vibyDatabaseProvider.overrideWithValue(db)],
  );
  addTearDown(() async => db.close());
  addTearDown(container.dispose);
  return (container, db);
}

void main() {
  test('defaults: system-follow on, Classic Dark, dynamic on', () async {
    final (ProviderContainer container, VibyDatabase _) = _setup();
    // Read defaults before hydration runs against the empty db.
    final ThemeSettingsState s = container.read(themeSettingsProvider);
    expect(s.systemFollow, isTrue);
    expect(s.themeId, 'classic_dark');
    expect(s.dynamicColor, isTrue);
    expect(s.amoledOverride, isFalse);
    await _settle();
  });

  test('selectTheme persists id + turns system-follow off', () async {
    final (ProviderContainer container, VibyDatabase db) = _setup();
    container.read(themeSettingsProvider);
    await _settle(); // let initial hydration settle before acting

    await container.read(themeSettingsProvider.notifier).selectTheme('nebula');

    final ThemeSettingsState s = container.read(themeSettingsProvider);
    expect(s.themeId, 'nebula');
    expect(s.systemFollow, isFalse);
    expect(await db.preferencesDao.get('theme_id'), 'nebula');
    expect(await db.preferencesDao.get('theme_system_follow'), '0');
  });

  test('amoled + dynamic toggles round-trip through drift', () async {
    final (ProviderContainer container, VibyDatabase db) = _setup();
    container.read(themeSettingsProvider);
    await _settle();

    final ThemeSettings c = container.read(themeSettingsProvider.notifier);
    await c.setAmoledOverride(true);
    await c.setDynamicColor(false);

    expect(await db.preferencesDao.get('theme_amoled'), '1');
    expect(await db.preferencesDao.get('dynamic_color'), '0');
    expect(container.read(themeSettingsProvider).amoledOverride, isTrue);
    expect(container.read(themeSettingsProvider).dynamicColor, isFalse);
  });

  test('persisted selection re-hydrates in a fresh container', () async {
    final (ProviderContainer container, VibyDatabase db) = _setup();
    await db.preferencesDao.set('theme_id', 'frost');
    await db.preferencesDao.set('theme_system_follow', '0');

    container.read(themeSettingsProvider); // triggers build + hydrate
    await _settle();

    final ThemeSettingsState s = container.read(themeSettingsProvider);
    expect(s.themeId, 'frost');
    expect(s.systemFollow, isFalse);
  });

  test('legacy theme_mode=amoled migrates to the new shape', () async {
    final (ProviderContainer container, VibyDatabase db) = _setup();
    await db.preferencesDao.set('theme_mode', 'amoled');

    container.read(themeSettingsProvider);
    await _settle();

    final ThemeSettingsState s = container.read(themeSettingsProvider);
    expect(s.systemFollow, isFalse);
    expect(s.themeId, 'classic_dark');
    expect(s.amoledOverride, isTrue);
  });

  test('legacy theme_mode=system migrates to system-follow', () async {
    final (ProviderContainer container, VibyDatabase db) = _setup();
    await db.preferencesDao.set('theme_mode', 'system');

    container.read(themeSettingsProvider);
    await _settle();

    expect(container.read(themeSettingsProvider).systemFollow, isTrue);
  });
}
