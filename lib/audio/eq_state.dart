/// A single equalizer band's current state, as surfaced to the UI. Carries the
/// platform-reported [centerFrequency] and the current [gain] (dB). No
/// just_audio types leak here, so UI/state may import this freely.
class EqBandState {
  const EqBandState({
    required this.index,
    required this.centerFrequency,
    required this.gain,
  });

  final int index;

  /// Center frequency in hertz (drives the axis label: "60 Hz", "3.6 kHz").
  final double centerFrequency;

  /// Current gain in decibels.
  final double gain;

  EqBandState copyWith({double? gain}) => EqBandState(
        index: index,
        centerFrequency: centerFrequency,
        gain: gain ?? this.gain,
      );
}

/// The whole equalizer as the UI sees it — a plain snapshot pushed on a stream.
///
/// [capable] is the capability flag (false on platforms with no EQ support, e.g.
/// iOS today — the UI shows a "not supported here" state). [discovered] is true
/// once the *real* platform band layout has loaded (before that, [bands] is a
/// sensible display fallback and audio isn't yet affected — the just_audio
/// equalizer only reports its bands after the player first connects).
class EqRuntimeState {
  const EqRuntimeState({
    required this.capable,
    required this.discovered,
    required this.enabled,
    required this.minDb,
    required this.maxDb,
    required this.bands,
    required this.loudnessGain,
    required this.activePresetId,
    required this.modified,
  });

  /// The "EQ unavailable on this platform" state.
  const EqRuntimeState.unsupported()
      : capable = false,
        discovered = false,
        enabled = false,
        minDb = -15,
        maxDb = 15,
        bands = const <EqBandState>[],
        loudnessGain = 0,
        activePresetId = null,
        modified = false;

  final bool capable;
  final bool discovered;
  final bool enabled;

  /// The min / max gain the platform allows (dB); also the slider range.
  final double minDb;
  final double maxDb;

  final List<EqBandState> bands;

  /// Loudness-enhancer target gain (dB); 0 = off.
  final double loudnessGain;

  /// Active preset id (built-in slug or `custom:…`), or null for a bespoke curve.
  final String? activePresetId;

  /// True when the current gains diverge from the active preset's curve — drives
  /// the "Custom (based on Rock)" + Save affordance.
  final bool modified;

  /// The current band gains, in band order (convenience for the curve painter).
  List<double> get gains =>
      bands.map((EqBandState b) => b.gain).toList(growable: false);

  /// The band center frequencies, in band order.
  List<double> get centerFrequencies =>
      bands.map((EqBandState b) => b.centerFrequency).toList(growable: false);

  EqRuntimeState copyWith({
    bool? capable,
    bool? discovered,
    bool? enabled,
    double? minDb,
    double? maxDb,
    List<EqBandState>? bands,
    double? loudnessGain,
    Object? activePresetId = _unset,
    bool? modified,
  }) {
    return EqRuntimeState(
      capable: capable ?? this.capable,
      discovered: discovered ?? this.discovered,
      enabled: enabled ?? this.enabled,
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      bands: bands ?? this.bands,
      loudnessGain: loudnessGain ?? this.loudnessGain,
      activePresetId: identical(activePresetId, _unset)
          ? this.activePresetId
          : activePresetId as String?,
      modified: modified ?? this.modified,
    );
  }

  static const Object _unset = Object();
}
