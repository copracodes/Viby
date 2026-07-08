import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../ui/theme/dynamic_theme.dart';
import 'database_providers.dart';
import 'library_providers.dart';
import 'queue_provider.dart';

part 'theme_providers.g.dart';

/// Persisted theme settings: the [VibyThemeMode] and whether album-art dynamic
/// colour is on.
class ThemeSettingsState {
  const ThemeSettingsState({required this.mode, required this.dynamicColor});

  final VibyThemeMode mode;
  final bool dynamicColor;

  ThemeSettingsState copyWith({VibyThemeMode? mode, bool? dynamicColor}) =>
      ThemeSettingsState(
        mode: mode ?? this.mode,
        dynamicColor: dynamicColor ?? this.dynamicColor,
      );
}

/// Owns the theme settings, persisting them to the [PreferencesDao]. `build()`
/// returns defaults synchronously (so the app can theme on first frame) then
/// hydrates from drift; setters update state and persist.
@Riverpod(keepAlive: true)
class ThemeSettings extends _$ThemeSettings {
  static const String _modeKey = 'theme_mode';
  static const String _dynamicKey = 'dynamic_color';

  @override
  ThemeSettingsState build() {
    unawaited(_hydrate());
    return const ThemeSettingsState(
      mode: VibyThemeMode.system,
      dynamicColor: true,
    );
  }

  Future<void> _hydrate() async {
    final dao = ref.read(vibyDatabaseProvider).preferencesDao;
    final String? modeStr = await dao.get(_modeKey);
    final String? dynStr = await dao.get(_dynamicKey);
    state = ThemeSettingsState(
      mode: _parseMode(modeStr) ?? state.mode,
      dynamicColor: dynStr == null ? state.dynamicColor : dynStr == '1',
    );
  }

  Future<void> setMode(VibyThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await ref.read(vibyDatabaseProvider).preferencesDao.set(_modeKey, mode.name);
  }

  Future<void> setDynamicColor(bool on) async {
    state = state.copyWith(dynamicColor: on);
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_dynamicKey, on ? '1' : '0');
  }

  static VibyThemeMode? _parseMode(String? name) {
    for (final VibyThemeMode m in VibyThemeMode.values) {
      if (m.name == name) return m;
    }
    return null;
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
/// fall back to [kBrandSeed]). This is the only place the seed is resolved, so
/// Now Playing and the mini-player share one extraction.
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
