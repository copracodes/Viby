import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/haptics.dart';
import 'database_providers.dart';

part 'haptics_providers.g.dart';

/// Whether subtle system haptics are on (Settings toggle). Persisted via the
/// [PreferencesDao]; defaults on, hydrated from drift.
@Riverpod(keepAlive: true)
class HapticsEnabled extends _$HapticsEnabled {
  static const String _key = 'haptics_enabled';

  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    final String? v =
        await ref.read(vibyDatabaseProvider).preferencesDao.get(_key);
    if (v != null) state = v == '1';
  }

  Future<void> setEnabled(bool on) async {
    state = on;
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_key, on ? '1' : '0');
  }
}

/// The app-wide [HapticsService], gated by [hapticsEnabledProvider].
@Riverpod(keepAlive: true)
HapticsService hapticsService(Ref ref) =>
    HapticsService(() => ref.read(hapticsEnabledProvider));
