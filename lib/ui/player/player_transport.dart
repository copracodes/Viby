import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_service.dart';
import '../../core/haptics.dart';
import '../../state/haptics_providers.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/tokens.dart';
import 'pressable_scale.dart';
import 'player_transition.dart';

/// The Now Playing transport row: shuffle · previous · play/pause · next.
///
/// Repeat moved to the secondary toolbar (Step 2.2 restructure) so the transport
/// stays uncluttered; shuffle stays here as a primary behaviour. A trailing
/// spacer that matches the shuffle control keeps the big play button optically
/// centred. The play/pause button is a filled circle with an [AnimatedIcon]
/// shape morph; every control has springy press feedback ([PressableScale]) and
/// the 1.4 disabled-state rules (dimmed + inert Next at the queue end, Previous
/// gated by [canGoPrevious]).
class PlayerTransport extends ConsumerWidget {
  const PlayerTransport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final QueueState queue = ref.watch(queueControllerProvider);
    final QueueController controller =
        ref.read(queueControllerProvider.notifier);
    final HapticsService haptics = ref.read(hapticsServiceProvider);
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;

    final bool canPrevious =
        canGoPrevious(hasPrevious: queue.hasPrevious, position: position);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _IconControl(
          icon: Icons.shuffle,
          tooltip: 'Shuffle',
          color: queue.shuffleOn ? scheme.primary : scheme.onSurfaceVariant,
          onTap: queue.isEmpty
              ? null
              : () {
                  haptics.selection();
                  controller.toggleShuffle();
                },
        ),
        _IconControl(
          icon: Icons.skip_previous,
          tooltip: 'Previous',
          size: 40,
          onTap: canPrevious
              ? () {
                  haptics.light();
                  controller.previous();
                }
              : null,
        ),
        const _PlayPauseButton(),
        _IconControl(
          icon: Icons.skip_next,
          tooltip: 'Next',
          size: 40,
          onTap: queue.hasNext
              ? () {
                  haptics.light();
                  controller.next();
                }
              : null,
        ),
        // Balances the shuffle control on the left so play stays centred.
        const SizedBox(width: _kControlSlot),
      ],
    );
  }
}

/// Footprint of a default [_IconControl] (icon 28 + Spacing.sm padding each
/// side) — used to balance the transport row so the play button is centred.
const double _kControlSlot = 28 + Spacing.sm * 2;

class _IconControl extends StatelessWidget {
  const _IconControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool enabled = onTap != null;
    final Color resolved = (color ?? scheme.onSurface)
        .withValues(alpha: enabled ? 1.0 : 0.35);
    return PressableScale(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Icon(icon, size: size, color: resolved),
        ),
      ),
    );
  }
}

/// Filled circular play/pause with a shape-morphing [AnimatedIcon].
class _PlayPauseButton extends ConsumerStatefulWidget {
  const _PlayPauseButton();

  @override
  ConsumerState<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends ConsumerState<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _icon = AnimationController(
    vsync: this,
    duration: Motion.base,
  );

  @override
  void dispose() {
    _icon.dispose();
    super.dispose();
  }

  void _sync(bool playing) {
    // 0 = play glyph, 1 = pause glyph.
    final double target = playing ? 1.0 : 0.0;
    if ((_icon.value - target).abs() > 0.001) {
      _icon.animateTo(target, curve: Motion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;
    _sync(playing);

    return PressableScale(
      onTap: () {
        ref.read(hapticsServiceProvider).light();
        final PlayerService service = ref.read(playerServiceProvider);
        playing ? service.pause() : service.play();
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AnimatedIcon(
            icon: AnimatedIcons.play_pause,
            progress: _icon,
            size: 40,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
