import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/loop_region.dart';
import 'package:viby/audio/player_service.dart';
import 'package:viby/core/haptics.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/ab_loop_provider.dart';
import 'package:viby/state/haptics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';

import '../support/fake_queue_sink.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'al',
      artistId: 'ar',
      filePath: '/m/$id.mp3',
    );

/// A stand-in [PlayerService] that only records the loop region (all the
/// [AbLoopController] touches on the player).
class _FakePlayer extends Fake implements PlayerService {
  final List<LoopRegion?> regions = <LoopRegion?>[];

  @override
  void setLoopRegion(LoopRegion? region) => regions.add(region);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSink sink;
  late _FakePlayer player;
  late StreamController<Duration> pos;
  late ProviderContainer container;

  setUp(() {
    sink = FakeSink();
    player = _FakePlayer();
    pos = StreamController<Duration>.broadcast();
    container = ProviderContainer(overrides: <Override>[
      queueSinkProvider.overrideWithValue(sink),
      playerServiceProvider.overrideWithValue(player),
      positionProvider.overrideWith((Ref ref) => pos.stream),
      hapticsServiceProvider.overrideWithValue(HapticsService(() => false)),
    ]);
    addTearDown(container.dispose);
    addTearDown(pos.close);
    // Keep the position provider alive so it retains the latest emitted value.
    container.listen(positionProvider, (_, __) {});
  });

  AbLoopController ab() => container.read(abLoopControllerProvider.notifier);
  AbLoopState state() => container.read(abLoopControllerProvider);
  QueueController queue() => container.read(queueControllerProvider.notifier);

  Future<void> seekTo(Duration d) async {
    pos.add(d);
    await _settle();
  }

  test('tap cycles set A → arm (mirrored to player) → clear', () async {
    await queue().setQueue(<Track>[_t('a')], autoPlay: false);

    await seekTo(const Duration(seconds: 5));
    ab().tap(); // set A at 5s
    expect(state(), const AbLoopPendingA(5000));

    await seekTo(const Duration(seconds: 8));
    ab().tap(); // set B at 8s → armed
    expect(state(), isA<AbLoopArmed>());
    expect(player.regions.last, const LoopRegion(aMs: 5000, bMs: 8000));

    ab().tap(); // clear
    expect(state(), const AbLoopInactive());
    expect(player.regions.last, isNull);
  });

  test('a track change cancels an armed loop (and clears the player)',
      () async {
    await queue().setQueue(<Track>[_t('a'), _t('b')], autoPlay: false);

    await seekTo(const Duration(seconds: 5));
    ab().tap();
    await seekTo(const Duration(seconds: 8));
    ab().tap();
    expect(state(), isA<AbLoopArmed>());

    // Simulate the player advancing to the next track (auto-advance / skip).
    sink.emitIndex(1);
    await _settle();

    expect(state(), const AbLoopInactive());
    expect(player.regions.last, isNull);
  });
}
