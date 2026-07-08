import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/eq_preset.dart';
import 'package:viby/audio/eq_service.dart';
import 'package:viby/audio/eq_state.dart';
import 'package:viby/core/haptics.dart';
import 'package:viby/data/db/viby_database.dart' show EqPresetRow;
import 'package:viby/state/eq_providers.dart';
import 'package:viby/state/haptics_providers.dart';
import 'package:viby/ui/screens/eq_screen.dart';
import 'package:viby/ui/theme/app_theme.dart';

/// A controllable in-memory [EqService] for widget tests (no just_audio).
class FakeEqService implements EqService {
  FakeEqService(this._state);

  EqRuntimeState _state;
  final StreamController<EqRuntimeState> _controller =
      StreamController<EqRuntimeState>.broadcast();

  final List<bool> enabledCalls = <bool>[];
  final List<EqPreset> appliedPresets = <EqPreset>[];
  final List<(int, double)> bandCalls = <(int, double)>[];

  @override
  EqRuntimeState get state => _state;

  @override
  Stream<EqRuntimeState> get stateStream => _controller.stream;

  @override
  bool get capable => _state.capable;

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledCalls.add(enabled);
    _state = _state.copyWith(enabled: enabled);
    _controller.add(_state);
  }

  @override
  Future<void> setBandGain(int index, double gainDb) async {
    bandCalls.add((index, gainDb));
  }

  @override
  Future<void> applyPreset(EqPreset preset) async {
    appliedPresets.add(preset);
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> setLoudnessTargetGain(double gainDb) async {}
  @override
  Future<String?> saveCustomPreset(String name) async => null;
  @override
  Future<void> renamePreset(String id, String name) async {}
  @override
  Future<void> deletePreset(String id) async {}
  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

EqRuntimeState _capableState({bool enabled = false}) {
  const List<double> freqs = <double>[60, 230, 910, 3600, 14000];
  return EqRuntimeState(
    capable: true,
    discovered: true,
    enabled: enabled,
    minDb: -15,
    maxDb: 15,
    bands: <EqBandState>[
      for (int i = 0; i < freqs.length; i++)
        EqBandState(index: i, centerFrequency: freqs[i], gain: 0),
    ],
    loudnessGain: 0,
    activePresetId: null,
    modified: false,
  );
}

Widget _app(FakeEqService service) => ProviderScope(
      overrides: <Override>[
        eqServiceProvider.overrideWith((Ref ref) => service),
        hapticsServiceProvider.overrideWithValue(HapticsService(() => false)),
        customEqPresetsProvider.overrideWith(
          (Ref ref) => Stream<List<EqPresetRow>>.value(const <EqPresetRow>[]),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const EqScreen()),
    );

void main() {
  testWidgets('renders master switch, bands and preset chips when capable',
      (WidgetTester tester) async {
    final FakeEqService service = FakeEqService(_capableState());
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    // Master switch present and off.
    expect(find.byType(SwitchListTile), findsOneWidget);
    // The five band sliders (the loudness slider is below the fold; the list
    // builds it lazily, so we only assert the bands here).
    expect(find.byType(Slider), findsAtLeastNWidgets(5));
    // Built-in preset chips.
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget);

    addTearDown(service.dispose);
  });

  testWidgets('toggling the master switch calls setEnabled',
      (WidgetTester tester) async {
    final FakeEqService service = FakeEqService(_capableState());
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(service.enabledCalls, <bool>[true]);

    addTearDown(service.dispose);
  });

  testWidgets('tapping a preset chip applies it', (WidgetTester tester) async {
    final FakeEqService service = FakeEqService(_capableState(enabled: true));
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(service.appliedPresets.single.id, 'rock');

    addTearDown(service.dispose);
  });

  testWidgets('shows the unsupported state when not capable',
      (WidgetTester tester) async {
    final FakeEqService service =
        FakeEqService(const EqRuntimeState.unsupported());
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(
      find.text('Equalizer not available on this device'),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNothing);

    addTearDown(service.dispose);
  });
}
