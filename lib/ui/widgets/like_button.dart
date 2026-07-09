import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/haptics_providers.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';

/// A heart toggle that likes/unlikes [trackId], reflecting the live liked state.
///
/// Outline ↔ filled, with a springy scale-pop on *like* and a selection-tick
/// haptic. Watches [trackLikedProvider] so it stays in sync everywhere (the
/// track sheet, Now Playing, list rows) as the state changes.
class LikeButton extends ConsumerStatefulWidget {
  const LikeButton({
    super.key,
    required this.trackId,
    this.size = 24,
    this.color,
  });

  final String trackId;
  final double size;

  /// Colour of the filled heart; defaults to the theme primary.
  final Color? color;

  @override
  ConsumerState<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends ConsumerState<LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: Motion.base,
    lowerBound: 0,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool currentlyLiked) async {
    final bool next = !currentlyLiked;
    ref.read(hapticsServiceProvider).selection();
    if (next) {
      // Pop 1 → 1.3 → 1 on like.
      _pop
        ..reset()
        ..forward();
    }
    await setTrackLiked(ref, widget.trackId, next);
  }

  @override
  Widget build(BuildContext context) {
    final bool liked =
        ref.watch(trackLikedProvider(widget.trackId)).valueOrNull ?? false;
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;

    return IconButton(
      onPressed: () => _toggle(liked),
      tooltip: liked ? 'Unlike' : 'Like',
      icon: ScaleTransition(
        // 1 → 1.3 → 1 pop, derived from the controller.
        scale: Tween<double>(begin: 1, end: 1.3).animate(
          TweenSequence<double>(<TweenSequenceItem<double>>[
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 0, end: 1)
                  .chain(CurveTween(curve: Curves.easeOut)),
              weight: 1,
            ),
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 1, end: 0)
                  .chain(CurveTween(curve: Curves.easeIn)),
              weight: 1,
            ),
          ]).animate(_pop),
        ),
        child: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          size: widget.size,
          color: liked ? color : null,
        ),
      ),
    );
  }
}
