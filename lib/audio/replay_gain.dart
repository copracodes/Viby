import 'dart:math' as math;

/// Which ReplayGain tag to normalize by.
///
/// `album` preserves the *relative* levels inside an album (a deliberately quiet
/// interlude stays quiet) and is the audiophile default; `track` levels every
/// song independently, which is what you want on shuffle.
enum ReplayGainMode { off, track, album }

/// The ReplayGain tags read off a file (all fields absent when untagged).
///
/// Gains are in dB relative to the ReplayGain reference level; peaks are the
/// sample peak as a fraction of full scale (1.0 = 0 dBFS), which is what lets us
/// normalize *without* clipping.
class ReplayGainInfo {
  const ReplayGainInfo({
    this.trackGainDb,
    this.trackPeak,
    this.albumGainDb,
    this.albumPeak,
  });

  final double? trackGainDb;
  final double? trackPeak;
  final double? albumGainDb;
  final double? albumPeak;

  bool get isEmpty =>
      trackGainDb == null &&
      albumGainDb == null &&
      trackPeak == null &&
      albumPeak == null;

  bool get hasGain => trackGainDb != null || albumGainDb != null;

  @override
  bool operator ==(Object other) =>
      other is ReplayGainInfo &&
      other.trackGainDb == trackGainDb &&
      other.trackPeak == trackPeak &&
      other.albumGainDb == albumGainDb &&
      other.albumPeak == albumPeak;

  @override
  int get hashCode =>
      Object.hash(trackGainDb, trackPeak, albumGainDb, albumPeak);
}

/// User settings for volume normalization.
class ReplayGainSettings {
  const ReplayGainSettings({
    this.mode = ReplayGainMode.off,
    this.preampDb = 0,
    this.preventClipping = true,
  });

  final ReplayGainMode mode;

  /// Manual offset applied on top of the file's gain, -6..+6 dB.
  final double preampDb;

  /// Whether to hold the volume below the level at which the file's own sample
  /// peak would clip. Only meaningful when the file carries a peak tag.
  final bool preventClipping;

  ReplayGainSettings copyWith({
    ReplayGainMode? mode,
    double? preampDb,
    bool? preventClipping,
  }) =>
      ReplayGainSettings(
        mode: mode ?? this.mode,
        preampDb: preampDb ?? this.preampDb,
        preventClipping: preventClipping ?? this.preventClipping,
      );

  @override
  bool operator ==(Object other) =>
      other is ReplayGainSettings &&
      other.mode == mode &&
      other.preampDb == preampDb &&
      other.preventClipping == preventClipping;

  @override
  int get hashCode => Object.hash(mode, preampDb, preventClipping);
}

/// Bounds of the pre-amp slider.
const double kPreampMinDb = -6;
const double kPreampMaxDb = 6;

/// The linear volume scalar to play a track at, from its tags and the settings.
///
/// Pure, so the whole normalization policy is one testable function:
///
/// * **Untagged files get 1.0** — never a fabricated level. Guessing a gain from
///   nothing is worse than doing nothing: it would make an untagged track jump
///   relative to its neighbours in a way the user can't predict. The pre-amp is
///   *part of the ReplayGain chain*, so it is not applied to them either.
///   (A file with a peak but no gain still gets clip protection, if enabled.)
/// * **Album mode falls back to the track gain** when a file has no album tag,
///   so a mixed library doesn't silently stop normalizing.
/// * **Clip protection caps, never boosts**: the scalar is held at or below
///   `1 / peak`, the point where the file's own loudest sample hits full scale.
/// * **The result is clamped to [0, 1]**: the platform's volume is an
///   attenuator, so a positive gain cannot amplify. ReplayGain in practice pulls
///   loud masters *down* to the reference, which is exactly what fits — and it
///   means the quiet-vs-loud pair evens out by lowering the loud one.
double replayGainScalar(ReplayGainInfo? info, ReplayGainSettings settings) {
  if (settings.mode == ReplayGainMode.off) return 1;
  if (info == null || info.isEmpty) return 1;

  final double? gainDb = switch (settings.mode) {
    ReplayGainMode.album => info.albumGainDb ?? info.trackGainDb,
    ReplayGainMode.track => info.trackGainDb,
    ReplayGainMode.off => null,
  };
  final double? peak = switch (settings.mode) {
    ReplayGainMode.album => info.albumPeak ?? info.trackPeak,
    ReplayGainMode.track => info.trackPeak,
    ReplayGainMode.off => null,
  };

  // No gain tag: no normalization (see the doc above) — but a peak tag can still
  // hold a hot master below clipping if the user asked for that.
  double scalar = gainDb == null
      ? 1
      : math.pow(10, (gainDb + settings.preampDb) / 20).toDouble();

  if (settings.preventClipping && peak != null && peak > 0) {
    scalar = math.min(scalar, 1 / peak);
  }
  return scalar.clamp(0.0, 1.0);
}
