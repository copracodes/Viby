import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../ui/theme/dynamic_theme.dart';
import '../ui/theme/theme_collection.dart';
import 'database_providers.dart';
import 'library_providers.dart';
import 'queue_provider.dart';

part 'theme_providers.g.dart';

/// Persisted appearance settings (Step 3.2):
/// - [themeId] — the selected [VibyTheme] from the collection.
/// - [systemFollow] — follow the platform light/dark, mapping to the Classic
///   pair (overrides [themeId] for resolution).
/// - [amoledOverride] — force pure-black surfaces on any dark theme.
/// - [dynamicColor] — let album art tint the accent on accepting themes.
class ThemeSettingsState {
  const ThemeSettingsState({
    required this.themeId,
    required this.systemFollow,
    required this.amoledOverride,
    required this.dynamicColor,
  });

  final String themeId;
  final bool systemFollow;
  final bool amoledOverride;
  final bool dynamicColor;

  ThemeSettingsState copyWith({
    String? themeId,
    bool? systemFollow,
    bool? amoledOverride,
    bool? dynamicColor,
  }) =>
      ThemeSettingsState(
        themeId: themeId ?? this.themeId,
        systemFollow: systemFollow ?? this.systemFollow,
        amoledOverride: amoledOverride ?? this.amoledOverride,
        dynamicColor: dynamicColor ?? this.dynamicColor,
      );
}

/// Owns appearance settings, persisting them to the [PreferencesDao] (the v4 KV
/// store — theme selection is a preference, so no schema migration is needed).
/// `build()` returns defaults synchronously (so the first frame themes
/// correctly) then hydrates from drift, including a one-time migration of the
/// legacy `theme_mode` value.
@Riverpod(keepAlive: true)
class ThemeSettings extends _$ThemeSettings {
  static const String _themeIdKey = 'theme_id';
  static const String _systemFollowKey = 'theme_system_follow';
  static const String _amoledKey = 'theme_amoled';
  static const String _dynamicKey = 'dynamic_color';
  static const String _legacyModeKey = 'theme_mode';

  @override
  ThemeSettingsState build() {
    unawaited(_hydrate());
    return const ThemeSettingsState(
      themeId: kDefaultThemeId,
      systemFollow: true,
      amoledOverride: false,
      dynamicColor: true,
    );
  }

  Future<void> _hydrate() async {
    final dao = ref.read(vibyDatabaseProvider).preferencesDao;
    final String? themeId = await dao.get(_themeIdKey);
    final String? dynStr = await dao.get(_dynamicKey);

    if (themeId == null) {
      // No new-format selection yet — migrate the legacy theme_mode value once.
      final ThemeSettingsState migrated =
          _fromLegacyMode(await dao.get(_legacyModeKey));
      state = migrated.copyWith(
        dynamicColor: dynStr == null ? state.dynamicColor : dynStr == '1',
      );
      return;
    }

    state = ThemeSettingsState(
      themeId: themeById(themeId) != null ? themeId : kDefaultThemeId,
      systemFollow: (await dao.get(_systemFollowKey)) == '1',
      amoledOverride: (await dao.get(_amoledKey)) == '1',
      dynamicColor: dynStr == null ? state.dynamicColor : dynStr == '1',
    );
  }

  /// Maps the pre-3.2 `theme_mode` value onto the new settings shape.
  ThemeSettingsState _fromLegacyMode(String? mode) {
    switch (mode) {
      case 'light':
        return state.copyWith(themeId: 'classic_light', systemFollow: false);
      case 'dark':
        return state.copyWith(themeId: 'classic_dark', systemFollow: false);
      case 'amoled':
        return state.copyWith(
          themeId: 'classic_dark',
          systemFollow: false,
          amoledOverride: true,
        );
      case 'system':
      default:
        return state.copyWith(systemFollow: true);
    }
  }

  /// Selects a specific theme (turns system-follow off).
  Future<void> selectTheme(String id) async {
    state = state.copyWith(themeId: id, systemFollow: false);
    final dao = ref.read(vibyDatabaseProvider).preferencesDao;
    await dao.set(_themeIdKey, id);
    await dao.set(_systemFollowKey, '0');
  }

  Future<void> setSystemFollow(bool on) async {
    state = state.copyWith(systemFollow: on);
    final dao = ref.read(vibyDatabaseProvider).preferencesDao;
    await dao.set(_systemFollowKey, on ? '1' : '0');
    // Ensure a themeId is persisted so a later hydrate uses the new format.
    await dao.set(_themeIdKey, state.themeId);
  }

  Future<void> setAmoledOverride(bool on) async {
    state = state.copyWith(amoledOverride: on);
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_amoledKey, on ? '1' : '0');
  }

  Future<void> setDynamicColor(bool on) async {
    state = state.copyWith(dynamicColor: on);
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_dynamicKey, on ? '1' : '0');
  }
}

/// The album-art palette extraction service (LRU + drift-cached).
@Riverpod(keepAlive: true)
DynamicThemeService dynamicThemeService(Ref ref) => DynamicThemeService(
      paletteDao: ref.watch(vibyDatabaseProvider).paletteDao,
      artworkDirectory: () => ref.read(artworkServiceProvider).directory(),
    );

/// The dynamic seed [Color] for the *currently-playing* track's artwork, or null
/// when dynamic colour is off / nothing is playing / no usable colour (callers
/// fall back to [kBrandSeed]). Whether it's actually applied is further gated by
/// the active theme's `acceptsDynamicSeed` (see `effectiveScheme`).
@riverpod
Future<Color?> currentSeed(Ref ref) async {
  final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
  if (!settings.dynamicColor) return null;
  final String? artworkKey = ref.watch(
    queueControllerProvider.select((QueueState q) => q.currentTrack?.artworkKey),
  );
  if (artworkKey == null) return null;
  return ref.watch(dynamicThemeServiceProvider).seedFor(artworkKey);
}

/// The dynamic seed [Color] for an artist's *derived portrait* (their most-played
/// album's art; see [artistArtworkProvider]), or null when the artist has no art
/// or no usable colour. Reuses the exact same extraction pipeline + LRU/drift
/// palette cache as [currentSeed] — no second extractor. Unlike [currentSeed] it
/// is NOT gated on the dynamic-colour setting: the artist-header tint is a
/// contextual header treatment (like Now Playing's backdrop), not a whole-app
/// recolour, per the dynamic-colour-is-contextual rule.
@riverpod
Future<Color?> artistSeed(Ref ref, String artistId) async {
  final String? artworkKey =
      await ref.watch(artistArtworkProvider(artistId).future);
  if (artworkKey == null) return null;
  return ref.watch(dynamicThemeServiceProvider).seedFor(artworkKey);
}
