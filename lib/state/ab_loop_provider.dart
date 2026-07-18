import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/loop_region.dart';
import '../core/haptics.dart';
import 'haptics_providers.dart';
import 'player_providers.dart';
import 'queue_provider.dart';

part 'ab_loop_provider.g.dart';

/// Owns the A–B repeat arming state (the single source of truth the Now Playing
/// chip and the progress-bar region both read) and mirrors an armed region into
/// the [PlayerService].
///
/// The audio layer independently cancels its own loop on a track change / skip;
/// this controller resets in lockstep by listening for the current track's id
/// changing, so the UI state can never disagree with the player.
@Riverpod(keepAlive: true)
class AbLoopController extends _$AbLoopController {
  @override
  AbLoopState build() {
    ref.listen<String?>(
      queueControllerProvider.select((QueueState q) => q.currentTrack?.id),
      (String? previous, String? next) {
        if (previous != next && state is! AbLoopInactive) _reset();
      },
    );
    return const AbLoopInactive();
  }

  /// Cycles the loop: set A → set B (arm) → clear. A second tap that isn't more
  /// than [kMinLoopSpanMs] past A is rejected with a denial haptic, so a mis-tap
  /// can't create a micro-loop.
  void tap() {
    final int positionMs =
        (ref.read(positionProvider).valueOrNull ?? Duration.zero).inMilliseconds;
    final AbLoopState next = nextAbState(state, positionMs);
    final HapticsService haptics = ref.read(hapticsServiceProvider);
    if (next == state) {
      haptics.reject();
      return;
    }
    state = next;
    switch (next) {
      case AbLoopArmed(:final LoopRegion region):
        ref.read(playerServiceProvider).setLoopRegion(region);
        haptics.selection();
      case AbLoopPendingA():
        haptics.light();
      case AbLoopInactive():
        ref.read(playerServiceProvider).setLoopRegion(null);
        haptics.light();
    }
  }

  /// Clears the loop (used by an explicit "off" affordance).
  void clear() {
    if (state is AbLoopInactive) return;
    _reset();
  }

  void _reset() {
    state = const AbLoopInactive();
    ref.read(playerServiceProvider).setLoopRegion(null);
  }
}
