import 'package:flutter/material.dart';

import 'dynamic_theme.dart';
import 'viby_theme.dart';

/// The Viby theme collection: the six shipped, named themes plus the pure
/// resolution logic (system-follow, amoled override, dynamic-seed gating).
///
/// Colour values here are hand-tuned starting points — the whole art direction
/// of a theme lives in its one definition, so an on-device tuning pass only
/// touches this file.

// --- Surface ramps ---------------------------------------------------------

/// Builds the five M3 container levels from a [base] surface by blending a tint
/// (white on dark themes, black on light) at increasing alpha — a coherent
/// elevation ramp for any art-directed base colour.
ColorScheme _withSurfaceRamp(ColorScheme scheme, Color base) {
  final bool dark = scheme.brightness == Brightness.dark;
  final Color tint = dark ? Colors.white : Colors.black;
  Color lvl(double a) => Color.alphaBlend(tint.withValues(alpha: a), base);
  return scheme.copyWith(
    surface: base,
    surfaceContainerLowest: dark ? lvl(0.0) : lvl(0.02),
    surfaceContainerLow: lvl(dark ? 0.03 : 0.04),
    surfaceContainer: lvl(dark ? 0.05 : 0.06),
    surfaceContainerHigh: lvl(dark ? 0.08 : 0.09),
    surfaceContainerHighest: lvl(dark ? 0.11 : 0.12),
  );
}

/// A scheme from [seed] at [brightness], with its surface ramp rebased on
/// [surface] and an optional [primary] override, holding the primary-on-surface
/// contrast guard.
ColorScheme _scheme(
  Color seed, {
  required Brightness brightness,
  required Color surface,
  Color? primary,
}) {
  ColorScheme s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  s = _withSurfaceRamp(s, surface);
  if (primary != null) s = s.copyWith(primary: primary);
  if (contrastRatio(s.primary, s.surface) < kMinContrast) {
    s = s.copyWith(primary: ensureContrast(s.primary, s.surface));
  }
  return s;
}

// --- The six themes --------------------------------------------------------

/// 1. Classic Light — the current light theme, unchanged id.
final VibyTheme classicLight = VibyTheme(
  id: 'classic_light',
  name: 'Classic Light',
  brightness: Brightness.light,
  scheme: schemeFromSeed(kBrandSeed, brightness: Brightness.light),
  background: SolidBackground(
    schemeFromSeed(kBrandSeed, brightness: Brightness.light).surface,
  ),
  surface: const OpaqueSurface(),
  acceptsDynamicSeed: true,
);

/// 2. Classic Dark — the current dark theme, unchanged id.
final VibyTheme classicDark = VibyTheme(
  id: 'classic_dark',
  name: 'Classic Dark',
  brightness: Brightness.dark,
  scheme: schemeFromSeed(kBrandSeed, brightness: Brightness.dark),
  background: SolidBackground(
    schemeFromSeed(kBrandSeed, brightness: Brightness.dark).surface,
  ),
  surface: const OpaqueSurface(),
  acceptsDynamicSeed: true,
);

/// 3. Midnight Aurora — near-black base with violet/blue/magenta glow blobs and
/// glass nav + sheets. Identity is locked (no dynamic seed).
VibyTheme _buildMidnightAurora() {
  const Color base = Color(0xFF0A0A0F);
  const Color violet = Color(0xFF7C4DFF);
  final ColorScheme scheme =
      _scheme(violet, brightness: Brightness.dark, surface: base, primary: violet);
  final AuroraBackground aurora = ensureBlobsReadable(
    const AuroraBackground(
      baseColor: base,
      blobs: <GlowBlob>[
        GlowBlob(
          color: Color(0xFF6A2CE0), // deep violet
          alignment: Alignment(-0.9, -0.9),
          radius: 0.9,
          opacity: 0.45,
        ),
        GlowBlob(
          color: Color(0xFF1E6BFF), // electric blue
          alignment: Alignment(1.1, -0.1),
          radius: 0.8,
          opacity: 0.38,
        ),
        GlowBlob(
          color: Color(0xFFD81E9B), // magenta
          alignment: Alignment(0.1, 1.1),
          radius: 0.95,
          opacity: 0.34,
        ),
      ],
    ),
    scheme.onSurface,
  );
  return VibyTheme(
    id: 'midnight_aurora',
    name: 'Midnight Aurora',
    brightness: Brightness.dark,
    scheme: scheme,
    background: aurora,
    surface: const GlassSurface(blurSigma: 24, tintAlpha: 0.42, borderAlpha: 0.14),
    acceptsDynamicSeed: false,
    isPro: true,
  );
}

/// 4. Nebula — deep purple→plum vertical wash, pink-magenta accent, tinted
/// surfaces, light text.
VibyTheme _buildNebula() {
  const Color base = Color(0xFF241033); // deep purple
  const Color plum = Color(0xFF3A1440);
  const Color accent = Color(0xFFFF4D9D); // pink-magenta
  final ColorScheme scheme =
      _scheme(accent, brightness: Brightness.dark, surface: base, primary: accent);
  return VibyTheme(
    id: 'nebula',
    name: 'Nebula',
    brightness: Brightness.dark,
    scheme: scheme,
    background: const LinearGradientBackground(
      colors: <Color>[Color(0xFF2E1145), base, plum],
      stops: <double>[0.0, 0.5, 1.0],
    ),
    surface: const TintedSurface(alpha: 0.55),
    acceptsDynamicSeed: false,
    isPro: true,
  );
}

/// 5. Frost — light theme: pale neutral base with a soft green-tinted top
/// gradient, frosted-glass cards, dark text, green accent.
VibyTheme _buildFrost() {
  const Color base = Color(0xFFF4F6F3); // pale neutral
  const Color green = Color(0xFF2E9E6B);
  final ColorScheme scheme =
      _scheme(green, brightness: Brightness.light, surface: base, primary: green);
  return VibyTheme(
    id: 'frost',
    name: 'Frost',
    brightness: Brightness.light,
    scheme: scheme,
    background: const LinearGradientBackground(
      colors: <Color>[Color(0xFFDDF0E4), base],
      stops: <double>[0.0, 0.55],
    ),
    surface: const GlassSurface(blurSigma: 18, tintAlpha: 0.6, borderAlpha: 0.5),
    acceptsDynamicSeed: false,
    isPro: true,
  );
}

/// 6. Onyx — charcoal neumorph-ish dark: elevated dual-tone surfaces, green glow
/// accent, NO blur (the performance-safe dark option). Accepts dynamic seed.
VibyTheme _buildOnyx() {
  const Color base = Color(0xFF17181A); // charcoal
  const Color green = Color(0xFF4ADE80);
  final ColorScheme scheme =
      _scheme(green, brightness: Brightness.dark, surface: base, primary: green);
  return VibyTheme(
    id: 'onyx',
    name: 'Onyx',
    brightness: Brightness.dark,
    scheme: scheme,
    background: const SolidBackground(base),
    surface: const TintedSurface(alpha: 0.9),
    acceptsDynamicSeed: true,
    isPro: true,
  );
}

final VibyTheme midnightAurora = _buildMidnightAurora();
final VibyTheme nebula = _buildNebula();
final VibyTheme frost = _buildFrost();
final VibyTheme onyx = _buildOnyx();

/// The shipped collection, in gallery order.
final List<VibyTheme> kThemeCollection = <VibyTheme>[
  classicLight,
  classicDark,
  midnightAurora,
  nebula,
  frost,
  onyx,
];

/// The default theme id (Classic Dark) when nothing is persisted.
const String kDefaultThemeId = 'classic_dark';

/// Looks up a theme by id, or null if unknown.
VibyTheme? themeById(String id) {
  for (final VibyTheme t in kThemeCollection) {
    if (t.id == id) return t;
  }
  return null;
}

// --- Resolution ------------------------------------------------------------

/// Rebases a dark theme onto pure-black surfaces (AMOLED override). Aurora blobs
/// survive on black; gradient/solid bases collapse to black. Light themes are
/// returned unchanged.
VibyTheme applyAmoled(VibyTheme theme) {
  if (!theme.isDark) return theme;
  final ColorScheme black = _withSurfaceRamp(theme.scheme, const Color(0xFF000000))
      .copyWith(
    surfaceContainerLowest: const Color(0xFF000000),
    surface: const Color(0xFF000000),
  );
  final BackgroundSpec bg = switch (theme.background) {
    AuroraBackground(:final List<GlowBlob> blobs) =>
      AuroraBackground(baseColor: const Color(0xFF000000), blobs: blobs),
    _ => const SolidBackground(Color(0xFF000000)),
  };
  return theme.copyWith(scheme: black, background: bg);
}

/// Resolves the active [VibyTheme] from the persisted settings + the platform
/// brightness. Pure, so it's unit-tested.
VibyTheme resolveActiveTheme({
  required String selectedId,
  required bool systemFollow,
  required Brightness platformBrightness,
  required bool amoledOverride,
}) {
  VibyTheme base;
  if (systemFollow) {
    base = platformBrightness == Brightness.dark ? classicDark : classicLight;
  } else {
    base = themeById(selectedId) ?? classicDark;
  }
  if (amoledOverride && base.isDark) base = applyAmoled(base);
  return base;
}

/// The scheme to actually render with: the theme's own scheme, unless dynamic
/// colour is on AND the theme [acceptsDynamicSeed] AND a [seed] is available —
/// then the accent family is swapped from the seed while the theme keeps its
/// surface/background identity. Primary stays contrast-guarded.
ColorScheme effectiveScheme(
  VibyTheme theme, {
  Color? seed,
  required bool dynamicColor,
}) {
  if (!dynamicColor || !theme.acceptsDynamicSeed || seed == null) {
    return theme.scheme;
  }
  final ColorScheme seeded =
      ColorScheme.fromSeed(seedColor: seed, brightness: theme.brightness);
  final ColorScheme swapped = theme.scheme.copyWith(
    primary: seeded.primary,
    onPrimary: seeded.onPrimary,
    primaryContainer: seeded.primaryContainer,
    onPrimaryContainer: seeded.onPrimaryContainer,
    secondary: seeded.secondary,
    onSecondary: seeded.onSecondary,
    tertiary: seeded.tertiary,
  );
  if (contrastRatio(swapped.primary, swapped.surface) < kMinContrast) {
    return swapped.copyWith(
      primary: ensureContrast(swapped.primary, swapped.surface),
    );
  }
  return swapped;
}
