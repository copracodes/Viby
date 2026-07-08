import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;

import '../../data/db/daos/palette_dao.dart';
import '../../data/sources/local/artwork_service.dart';

/// Brand seed — the static purple. Used when there's no artwork, the art is
/// near-monochrome, or dynamic colour is turned off. Matches `AppTheme.seed`.
const Color kBrandSeed = Color(0xFF7C4DFF);

/// Minimum WCAG contrast we hold primary-on-surface to.
const double kMinContrast = 4.5;

/// The user-facing theme choices. [amoled] is a dark variant with pure-black
/// surfaces (OLED power saving + deep look).
enum VibyThemeMode { system, light, dark, amoled }

// --- Contrast (WCAG) -------------------------------------------------------

/// WCAG relative-contrast ratio between two colours (1.0 .. 21.0).
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Nudges [color]'s lightness away from [against] until it clears [minRatio]
/// contrast (or the lightness bound is reached). Hue and saturation are kept, so
/// the adjusted colour still reads as "the same colour, more legible".
Color ensureContrast(Color color, Color against, {double minRatio = kMinContrast}) {
  if (contrastRatio(color, against) >= minRatio) return color;
  final HSLColor hsl = HSLColor.fromColor(color);
  // Push toward white on dark backgrounds, toward black on light ones.
  final double direction = against.computeLuminance() < 0.5 ? 1.0 : -1.0;
  double lightness = hsl.lightness;
  Color best = color;
  for (int i = 0; i < 20; i++) {
    lightness = (lightness + direction * 0.05).clamp(0.0, 1.0);
    best = hsl.withLightness(lightness).toColor();
    if (contrastRatio(best, against) >= minRatio) break;
  }
  return best;
}

// --- Seed selection --------------------------------------------------------

/// True when [color] is near-monochrome (low saturation) — dynamic theming
/// would yield a lifeless scheme, so callers fall back to the brand seed.
bool isNearMonochrome(Color color, {double minSaturation = 0.15}) {
  return HSLColor.fromColor(color).saturation < minSaturation;
}

/// Chooses a seed colour from a generated [palette]: prefer a vibrant swatch,
/// then the dominant one. Returns null when nothing usable is found or the best
/// candidate is near-monochrome (→ brand fallback).
Color? seedFromPalette(PaletteGenerator palette) {
  final Color? candidate = palette.vibrantColor?.color ??
      palette.lightVibrantColor?.color ??
      palette.darkVibrantColor?.color ??
      palette.dominantColor?.color;
  if (candidate == null || isNearMonochrome(candidate)) return null;
  return candidate;
}

// --- Scheme building -------------------------------------------------------

/// Pure-black surface ramp for the AMOLED variant.
ColorScheme _amoledSurfaces(ColorScheme scheme) => scheme.copyWith(
      surface: const Color(0xFF000000),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF101010),
      surfaceContainerHigh: const Color(0xFF161616),
      surfaceContainerHighest: const Color(0xFF1E1E1E),
    );

/// Builds a Material 3 [ColorScheme] from [seed] for [brightness], enforcing the
/// primary-on-surface contrast guard and applying pure-black surfaces when
/// [amoled]. `ColorScheme.fromSeed` already yields good tonal contrast, so the
/// guard is a defensive net for a pathological seed.
ColorScheme schemeFromSeed(
  Color seed, {
  required Brightness brightness,
  bool amoled = false,
}) {
  ColorScheme scheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  if (amoled && brightness == Brightness.dark) {
    scheme = _amoledSurfaces(scheme);
  }
  if (contrastRatio(scheme.primary, scheme.surface) < kMinContrast) {
    scheme =
        scheme.copyWith(primary: ensureContrast(scheme.primary, scheme.surface));
  }
  return scheme;
}

// --- LRU cache -------------------------------------------------------------

/// A tiny fixed-capacity LRU cache. Reads and writes mark the key most-recent;
/// inserting past [maxSize] evicts the least-recently-used entry.
class LruCache<K, V> {
  LruCache(this.maxSize) : assert(maxSize > 0, 'maxSize must be positive');

  final int maxSize;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  int get length => _entries.length;
  bool containsKey(K key) => _entries.containsKey(key);

  V? get(K key) {
    final V? value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value; // reinsert as most-recently-used
    return value;
  }

  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > maxSize) _entries.remove(_entries.keys.first);
  }
}

// --- Extraction service ----------------------------------------------------

/// Resolves the dominant seed colour for an artwork, memoised through an
/// in-memory LRU and the drift [PaletteDao] (so cold start themes instantly),
/// falling back to on-the-fly `palette_generator` extraction.
class DynamicThemeService {
  DynamicThemeService({
    required PaletteDao paletteDao,
    required Future<Directory> Function() artworkDirectory,
    int lruSize = 50,
  })  : _paletteDao = paletteDao,
        _artworkDirectory = artworkDirectory,
        _lru = LruCache<String, int>(lruSize);

  final PaletteDao _paletteDao;
  final Future<Directory> Function() _artworkDirectory;
  final LruCache<String, int> _lru;

  /// The seed [Color] for [artworkKey], or null when there's no key or no
  /// usable colour (caller uses [kBrandSeed]). Order: LRU → drift → extract.
  Future<Color?> seedFor(String? artworkKey) async {
    if (artworkKey == null) return null;
    final int? cached = _lru.get(artworkKey);
    if (cached != null) return Color(cached);

    final int? persisted = await _paletteDao.getSeed(artworkKey);
    if (persisted != null) {
      _lru.put(artworkKey, persisted);
      return Color(persisted);
    }

    final Color? extracted = await _extract(artworkKey);
    if (extracted == null) return null;
    final int argb = extracted.toARGB32();
    _lru.put(artworkKey, argb);
    await _paletteDao.putSeed(artworkKey, argb);
    return extracted;
  }

  Future<Color?> _extract(String artworkKey) async {
    try {
      final Directory dir = await _artworkDirectory();
      final File file =
          File(p.join(dir.path, ArtworkService.fileNameFor(artworkKey)));
      if (!file.existsSync()) return null;
      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        FileImage(file),
        maximumColorCount: 16,
      );
      return seedFromPalette(palette);
    } catch (_) {
      return null; // never let theming break on a bad image
    }
  }
}
