import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The "PRO" pill shown on Pro-marked features. Purely a marker — gating is
/// decided by `kProThemesUnlocked` (see `core/pro.dart`). Uses the scheme's
/// tertiary so it reads as a distinct accent in every theme.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiary,
        borderRadius: Radii.brFull,
      ),
      child: Text(
        'PRO',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiary,
              fontWeight: VibyType.bold,
              letterSpacing: 0.5,
              height: 1,
            ),
      ),
    );
  }
}
