import 'package:flutter/material.dart';

import '../theme/app_background.dart';
import '../theme/tokens.dart';
import '../theme/viby_theme.dart';
import 'pro_badge.dart';

/// A live preview card for a [VibyTheme]: the theme's real background with a
/// faux mini-player + accent chip painted in the theme's own colours, so the
/// gallery shows exactly how each theme looks. Ringed when [selected].
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final VibyTheme theme;
  final bool selected;
  final VoidCallback onTap;

  static const double _width = 128;
  static const double _height = 150;

  @override
  Widget build(BuildContext context) {
    final ColorScheme ambient = Theme.of(context).colorScheme;
    final ColorScheme scheme = theme.scheme;
    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              height: _height,
              decoration: BoxDecoration(
                borderRadius: Radii.brLg,
                border: Border.all(
                  color: selected ? ambient.primary : ambient.outlineVariant,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: Radii.brLg,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AppBackground(
                      background: theme.background,
                      child: _MiniMock(scheme: scheme, surface: theme.surface),
                    ),
                    if (theme.isPro)
                      const Positioned(
                        top: Spacing.sm,
                        right: Spacing.sm,
                        child: ProBadge(),
                      ),
                    if (selected)
                      Positioned(
                        top: Spacing.sm,
                        left: Spacing.sm,
                        child: Icon(Icons.check_circle,
                            size: 20, color: ambient.primary),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            theme.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight:
                      selected ? VibyType.semibold : VibyType.regular,
                ),
          ),
        ],
      ),
    );
  }
}

/// A faux mini-player + accent chip in the previewed theme's colours.
class _MiniMock extends StatelessWidget {
  const _MiniMock({required this.scheme, required this.surface});

  final ColorScheme scheme;
  final SurfaceSpec surface;

  Color get _surfaceColor => switch (surface) {
        OpaqueSurface() => scheme.surfaceContainer,
        TintedSurface(:final double alpha) =>
          scheme.surfaceContainerHigh.withValues(alpha: alpha),
        GlassSurface(:final double tintAlpha) =>
          scheme.surfaceContainerHigh.withValues(alpha: tintAlpha),
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Accent chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: Radii.brFull,
            ),
            child: SizedBox(
              width: 26,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.onPrimary,
                  borderRadius: Radii.brFull,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Faux mini-player.
          Container(
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: Radii.brMd,
              border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: Radii.brSm,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Bar(color: scheme.onSurface.withValues(alpha: 0.8), width: 46),
                      const SizedBox(height: 4),
                      _Bar(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                        width: 30,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.play_arrow, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(color: color, borderRadius: Radii.brFull),
    );
  }
}
