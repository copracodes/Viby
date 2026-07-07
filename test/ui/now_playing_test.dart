import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/screens/now_playing_screen.dart';
import 'package:viby/ui/theme/app_theme.dart';

import '../support/fake_queue_sink.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album',
      artistId: 'artist',
      artistName: 'A Band',
      filePath: '/music/$id.mp3',
    );

ProviderContainer _container(
  FakeSink sink, {
  Duration position = Duration.zero,
}) {
  return ProviderContainer(
    overrides: <Override>[
      queueSinkProvider.overrideWithValue(sink),
      playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
      positionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(position)),
      bufferedPositionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
      trackDurationProvider.overrideWith(
        (Ref ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
      ),
      artworkDirectoryProvider.overrideWith(
        (Ref ref) => Future<Directory>.value(Directory.systemTemp),
      ),
    ],
  );
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const NowPlayingScreen(),
      ),
    );

VoidCallback? _onPressedFor(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed;

void main() {
  testWidgets('transport buttons dispatch the right queue operations', (
    WidgetTester tester,
  ) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    // Start mid-queue so both prev and next are live.
    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('a'), _t('b'), _t('c')], startIndex: 1);
    sink.calls.clear();

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // Next / previous delegate straight to the sink.
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();
    expect(sink.calls, contains('next'));

    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pumpAndSettle();
    expect(sink.calls, contains('prev'));

    // Shuffle reorders the queue in place (engine-side shuffle).
    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();
    expect(sink.calls.any((String c) => c.startsWith('reorder(')), isTrue);
    expect(container.read(queueControllerProvider).shuffleOn, isTrue);

    // Repeat cycles off → all and mirrors the loop mode to the sink.
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    expect(sink.calls, contains('repeat(all)'));
  });

  testWidgets('a single-track queue dims Next and Previous', (
    WidgetTester tester,
  ) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('only')]);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // No next track and <3s in → both disabled (onPressed == null).
    expect(_onPressedFor(tester, Icons.skip_next), isNull);
    expect(_onPressedFor(tester, Icons.skip_previous), isNull);
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

    expect(_onPressedFor(tester, Icons.skip_next), isNull); // still no next
    expect(_onPressedFor(tester, Icons.skip_previous), isNotNull);
  });
}
