import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

import '../data/db/daos/eq_dao.dart';
import '../data/db/viby_database.dart' show EqPresetRow, EqSettingsRow;
import 'eq_preset.dart';
import 'eq_state.dart';

/// Fallback band layout shown before the platform reports its real bands (a
/// standard 5-band octave spread). Purely for display; audio is only affected
/// once the real [AndroidEqualizerParameters] resolve.
const List<double> _kFallbackBands = <double>[60, 230, 910, 3600, 14000];

/// The platform EQ effects + the [AudioPipeline] they plug into.
///
/// This is the **capability-flag seam** (see CLAUDE.md): [build] returns a
/// [capable] engine only on Android, where it constructs the real
/// [AndroidEqualizer] + [AndroidLoudnessEnhancer]; elsewhere it returns a
/// no-op engine with a null pipeline. It exists so `main()` can build the
/// effects *before* the player (they must be attached at player construction)
/// and hand the pipeline to the audio handler, while the [EqService] drives the
/// same effect instances. `state/` holds this opaquely and never touches its
/// just_audio fields.
class EqEngine {
  EqEngine._({
    required this.pipeline,
    required this.capable,
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudness,
  })  : _equalizer = equalizer,
        _loudness = loudness;

  /// The pipeline to attach to the player (null when not [capable]).
  final AudioPipeline? pipeline;

  /// Whether this platform supports the equalizer.
  final bool capable;

  final AndroidEqualizer? _equalizer;
  final AndroidLoudnessEnhancer? _loudness;

  /// Builds the engine for the current platform. Android → real effects +
  /// pipeline; everything else → a no-op engine (iOS support can add a Darwin
  /// branch here later without touching callers).
  factory EqEngine.build() {
    final bool android = !kIsWeb && Platform.isAndroid;
    if (!android) {
      return EqEngine._(pipeline: null, capable: false);
    }
    final AndroidEqualizer equalizer = AndroidEqualizer();
    final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();
    return EqEngine._(
      pipeline: AudioPipeline(
        androidAudioEffects: <AndroidAudioEffect>[equalizer, loudness],
      ),
      capable: true,
      equalizer: equalizer,
      loudness: loudness,
    );
  }

  /// A never-capable engine, for tests / non-Android provider wiring.
  factory EqEngine.noop() => EqEngine._(pipeline: null, capable: false);
}

/// The equalizer controller as UI/state see it. Hides just_audio; exposes a
/// reactive [EqRuntimeState] plus real-time mutation methods. Two impls:
/// [PlatformEqService] (drives a real [EqEngine]) and [NoopEqService].
abstract class EqService {
  EqRuntimeState get state;
  Stream<EqRuntimeState> get stateStream;
  bool get capable;

  /// Loads persisted settings and applies them to the effect pipeline. Called
  /// once at app init, before first playback, so the EQ is already armed when
  /// audio starts (band gains land as soon as the platform reports its bands).
  Future<void> restore();

  Future<void> setEnabled(bool enabled);
  Future<void> setBandGain(int index, double gainDb);
  Future<void> setLoudnessTargetGain(double gainDb);
  Future<void> applyPreset(EqPreset preset);

  /// Saves the current curve as a named custom preset; returns its new id.
  Future<String?> saveCustomPreset(String name);
  Future<void> renamePreset(String id, String name);
  Future<void> deletePreset(String id);

  Future<void> dispose();
}

/// The real equalizer service, driving an Android [EqEngine] and persisting to
/// the [EqDao]. Gain/preset writes are real-time (they hit the platform effect
/// immediately once bands are live) and debounced only by drift's own batching.
class PlatformEqService implements EqService {
  PlatformEqService(this._engine, this._dao) {
    _state = EqRuntimeState(
      capable: _engine.capable,
      discovered: false,
      enabled: false,
      minDb: -15,
      maxDb: 15,
      bands: _bandsFor(_kFallbackBands, const <double>[]),
      loudnessGain: 0,
      activePresetId: null,
      modified: false,
    );
  }

  final EqEngine _engine;
  final EqDao _dao;

  final StreamController<EqRuntimeState> _controller =
      StreamController<EqRuntimeState>.broadcast();

  late EqRuntimeState _state;

  /// The active preset (built-in or re-hydrated custom), used to recompute the
  /// modified flag whenever gains or the band layout change.
  EqPreset? _activePreset;

  /// The live platform parameters, once discovered (null before first playback).
  AndroidEqualizerParameters? _params;

  @override
  EqRuntimeState get state => _state;

  @override
  Stream<EqRuntimeState> get stateStream => _controller.stream;

  @override
  bool get capable => _engine.capable;

  List<double> get _freqs => _state.centerFrequencies;

  @override
  Future<void> restore() async {
    if (!_engine.capable) return;
    EqSettingsRow? row;
    try {
      row = await _dao.getSettings();
    } catch (e, st) {
      developer.log('eq restore: read failed', error: e, stackTrace: st);
    }
    final bool enabled = row?.enabled ?? false;
    final double loudness = row?.loudnessGain ?? 0;
    final String? presetId = row?.activePresetId;
    final Map<double, double> savedGains = decodeGainMap(row?.bandGainsJson);

    // Display bands: the frequencies the curve was saved at (so the exact saved
    // shape shows on cold start), or the fallback layout when nothing's saved.
    final List<double> displayFreqs = savedGains.isNotEmpty
        ? (savedGains.keys.toList()..sort())
        : _kFallbackBands;
    final List<double> displayGains = gainsForBands(savedGains, displayFreqs);

    _activePreset = await _resolvePreset(presetId, savedGains);

    _state = _state.copyWith(
      enabled: enabled,
      loudnessGain: loudness,
      activePresetId: presetId,
      bands: _bandsFor(displayFreqs, displayGains),
      modified: _computeModified(displayFreqs, displayGains),
    );
    _emit();

    // Arm the effects. Enable + loudness apply pre-playback (they buffer on the
    // effect and flush on activation); band gains land when [parameters]
    // resolves (first playback), reconciled onto the real band layout.
    try {
      await _engine._loudness?.setTargetGain(loudness);
      await _engine._loudness?.setEnabled(enabled);
      await _engine._equalizer?.setEnabled(enabled);
    } catch (e, st) {
      developer.log('eq restore: arm failed', error: e, stackTrace: st);
    }
    unawaited(_discoverBands(savedGains));
  }

  /// Awaits the platform band parameters and reconciles saved gains onto them.
  Future<void> _discoverBands(Map<double, double> savedGains) async {
    final AndroidEqualizer? eq = _engine._equalizer;
    if (eq == null) return;
    try {
      final AndroidEqualizerParameters params = await eq.parameters;
      _params = params;
      final List<double> freqs = params.bands
          .map((AndroidEqualizerBand b) => b.centerFrequency)
          .toList(growable: false);
      // Prefer the saved curve; if none, keep whatever's showing (flat).
      final List<double> gains = savedGains.isNotEmpty
          ? gainsForBands(savedGains, freqs)
          : List<double>.filled(freqs.length, 0);
      for (int i = 0; i < params.bands.length; i++) {
        await params.bands[i].setGain(gains[i]);
      }
      _state = _state.copyWith(
        discovered: true,
        minDb: params.minDecibels,
        maxDb: params.maxDecibels,
        bands: _bandsFor(freqs, gains),
        modified: _computeModified(freqs, gains),
      );
      _emit();
    } catch (e, st) {
      developer.log('eq band discovery failed', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _state = _state.copyWith(enabled: enabled);
    _emit();
    try {
      await _engine._equalizer?.setEnabled(enabled);
      await _engine._loudness?.setEnabled(enabled);
    } catch (e, st) {
      developer.log('eq setEnabled failed', error: e, stackTrace: st);
    }
    await _persist(enabled: enabled);
  }

  @override
  Future<void> setBandGain(int index, double gainDb) async {
    if (index < 0 || index >= _state.bands.length) return;
    final double snapped = snapToDetent(gainDb);
    final List<EqBandState> bands = List<EqBandState>.of(_state.bands);
    bands[index] = bands[index].copyWith(gain: snapped);
    final List<double> gains =
        bands.map((EqBandState b) => b.gain).toList(growable: false);
    _state = _state.copyWith(
      bands: bands,
      modified: _computeModified(_freqs, gains),
    );
    _emit();
    // Real-time: push straight to the platform band (no-op until discovered).
    try {
      final AndroidEqualizerParameters? p = _params;
      if (p != null && index < p.bands.length) {
        await p.bands[index].setGain(snapped);
      }
    } catch (e, st) {
      developer.log('eq setBandGain failed', error: e, stackTrace: st);
    }
    await _persist(bandGainsJson: encodeGainMap(gainMapFor(_freqs, gains)));
  }

  @override
  Future<void> setLoudnessTargetGain(double gainDb) async {
    _state = _state.copyWith(loudnessGain: gainDb);
    _emit();
    try {
      await _engine._loudness?.setTargetGain(gainDb);
    } catch (e, st) {
      developer.log('eq loudness failed', error: e, stackTrace: st);
    }
    await _persist(loudnessGain: gainDb);
  }

  @override
  Future<void> applyPreset(EqPreset preset) async {
    _activePreset = preset;
    final List<double> gains = normalizeCurveToBands(preset.curve, _freqs);
    final List<EqBandState> bands = <EqBandState>[
      for (int i = 0; i < _state.bands.length; i++)
        _state.bands[i].copyWith(gain: i < gains.length ? gains[i] : 0),
    ];
    _state = _state.copyWith(
      bands: bands,
      activePresetId: preset.id,
      modified: false,
    );
    _emit();
    try {
      final AndroidEqualizerParameters? p = _params;
      if (p != null) {
        for (int i = 0; i < p.bands.length && i < gains.length; i++) {
          await p.bands[i].setGain(gains[i]);
        }
      }
    } catch (e, st) {
      developer.log('eq applyPreset failed', error: e, stackTrace: st);
    }
    await _persist(
      touchPreset: true,
      presetId: preset.id,
      bandGainsJson: encodeGainMap(gainMapFor(_freqs, gains)),
    );
  }

  @override
  Future<String?> saveCustomPreset(String name) async {
    final List<double> gains = _state.gains;
    final String json = encodeGainMap(gainMapFor(_freqs, gains));
    String? id;
    try {
      id = await _dao.insertCustomPreset(name, json);
    } catch (e, st) {
      developer.log('eq saveCustomPreset failed', error: e, stackTrace: st);
      return null;
    }
    _activePreset =
        EqPreset.fromGainMap(id: id, name: name, gains: gainMapFor(_freqs, gains));
    _state = _state.copyWith(activePresetId: id, modified: false);
    _emit();
    await _persist(touchPreset: true, presetId: id);
    return id;
  }

  @override
  Future<void> renamePreset(String id, String name) async {
    try {
      await _dao.renameCustomPreset(id, name);
      if (_activePreset?.id == id) {
        _activePreset = EqPreset(
          id: id,
          name: name,
          curve: _activePreset!.curve,
          builtIn: false,
        );
        _emit();
      }
    } catch (e, st) {
      developer.log('eq renamePreset failed', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> deletePreset(String id) async {
    try {
      await _dao.deleteCustomPreset(id);
    } catch (e, st) {
      developer.log('eq deletePreset failed', error: e, stackTrace: st);
    }
    if (_state.activePresetId == id) {
      _activePreset = null;
      _state = _state.copyWith(activePresetId: null, modified: false);
      _emit();
      await _persist(touchPreset: true, presetId: null);
    }
  }

  @override
  Future<void> dispose() => _controller.close();

  // --- helpers -------------------------------------------------------------

  List<EqBandState> _bandsFor(List<double> freqs, List<double> gains) {
    return <EqBandState>[
      for (int i = 0; i < freqs.length; i++)
        EqBandState(
          index: i,
          centerFrequency: freqs[i],
          gain: i < gains.length ? gains[i] : 0,
        ),
    ];
  }

  bool _computeModified(List<double> freqs, List<double> gains) {
    final EqPreset? active = _activePreset;
    if (active == null) return false;
    return !gainsMatch(gains, normalizeCurveToBands(active.curve, freqs));
  }

  Future<EqPreset?> _resolvePreset(
    String? presetId,
    Map<double, double> savedGains,
  ) async {
    if (presetId == null) return null;
    final EqPreset? builtIn = builtInPresetById(presetId);
    if (builtIn != null) return builtIn;
    try {
      final EqPresetRow? row = await _dao.getCustomPreset(presetId);
      if (row == null) return null;
      return EqPreset.fromGainMap(
        id: row.id,
        name: row.name,
        gains: decodeGainMap(row.gainsJson),
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists the given fields. [touchPreset] distinguishes "leave the stored
  /// preset id alone" (false — the DAO field stays absent) from "write
  /// [presetId], possibly null" (true), avoiding a shared-sentinel dependency
  /// with the DAO.
  Future<void> _persist({
    bool? enabled,
    double? loudnessGain,
    bool touchPreset = false,
    String? presetId,
    String? bandGainsJson,
  }) async {
    try {
      if (touchPreset) {
        await _dao.saveSettings(
          enabled: enabled,
          loudnessGain: loudnessGain,
          activePresetId: presetId,
          bandGainsJson: bandGainsJson,
        );
      } else {
        await _dao.saveSettings(
          enabled: enabled,
          loudnessGain: loudnessGain,
          bandGainsJson: bandGainsJson,
        );
      }
    } catch (e, st) {
      developer.log('eq persist failed', error: e, stackTrace: st);
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_state);
  }
}

/// The no-op service used where the platform has no equalizer (iOS/desktop/web).
/// Behaves like a permanently-unsupported, empty EQ so callers need no branch.
class NoopEqService implements EqService {
  NoopEqService();

  static const EqRuntimeState _state = EqRuntimeState.unsupported();

  @override
  EqRuntimeState get state => _state;

  @override
  Stream<EqRuntimeState> get stateStream =>
      Stream<EqRuntimeState>.value(_state);

  @override
  bool get capable => false;

  @override
  Future<void> restore() async {}
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> setBandGain(int index, double gainDb) async {}
  @override
  Future<void> setLoudnessTargetGain(double gainDb) async {}
  @override
  Future<void> applyPreset(EqPreset preset) async {}
  @override
  Future<String?> saveCustomPreset(String name) async => null;
  @override
  Future<void> renamePreset(String id, String name) async {}
  @override
  Future<void> deletePreset(String id) async {}
  @override
  Future<void> dispose() async {}
}
