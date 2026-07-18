import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/haptics.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/haptics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/player/player_transport.dart';
import 'package:viby/ui/player/pressable_scale.dart';
import 'package:viby/ui/theme/app_theme.dart';

import '../../support/fake_queue_sink.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album',
      artistId: 'artist',
      artistName: 'A Band',
      filePath: '/music/$id.mp3',
    );

ProviderContainer _container(FakeSink sink, {Duration position = Duration.zero}) {
  return ProviderContainer(
    overrides: <Override>[
      queueSinkProvider.overrideWithValue(sink),
      hapticsServiceProvider.overrideWithValue(HapticsService(() => false)),
      playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
      positionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(position)),
    ],
  );
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(child: PlayerTransport()),
        ),
      ),
    );

/// The PressableScale wrapping a given control icon (null onTap == disabled).
PressableScale _controlFor(WidgetTester tester, IconData icon) =>
    tester.widget<PressableScale>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(PressableScale),
      ),
    );

void main() {
  testWidgets('transport buttons dispatch the right queue operations',
      (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('a'), _t('b'), _t('c')], startIndex: 1);
    sink.calls.clear();

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();
    expect(sink.calls, contains('next'));

    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pumpAndSettle();
    expect(sink.calls, contains('prev'));

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();
    expect(sink.calls.any((String c) => c.startsWith('reorder(')), isTrue);
    expect(container.read(queueControllerProvider).shuffleOn, isTrue);

    // Repeat is no longer in the transport (it moved to the secondary toolbar).
    expect(find.byIcon(Icons.repeat), findsNothing);
  });

  testWidgets('a single-track queue dims Next and Previous',
      (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('only')]);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(_controlFor(tester, Icons.skip_next).onTap, isNull);
    expect(_controlFor(tester, Icons.skip_previous).onTap, isNull);
  });

  testWidgets('past 3s, Previous re-enables (restart) even with no prior track',
      (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container =
        _container(sink, position: const Duration(seconds: 5));
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('only')]);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(_controlFor(tester, Icons.skip_next).onTap, isNull);
    expect(_controlFor(tester, Icons.skip_previous).onTap, isNotNull);
  });
}
