import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/haptics.dart';
import 'package:viby/data/db/tables.dart' show RepeatMode, TrackSource;
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/state/haptics_providers.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/player/secondary_toolbar.dart';
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

ProviderContainer _container(FakeSink sink) => ProviderContainer(
      overrides: <Override>[
        queueSinkProvider.overrideWithValue(sink),
        hapticsServiceProvider.overrideWithValue(HapticsService(() => false)),
        trackLikedProvider('a')
            .overrideWith((Ref ref) => Stream<bool>.value(false)),
        currentLyricsProvider.overrideWith((Ref ref) async => const Lyrics.none()),
      ],
    );

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SecondaryToolbar(
              trackId: 'a',
              onOpenQueue: () {},
              onOpenLyrics: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('repeat lives in the toolbar and cycles off → all → one',
      (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('a'), _t('b')]);
    sink.calls.clear();

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // Off → all: the repeat glyph shows, the controller state advances, and the
    // change is mirrored to the sink (which is what persistence reads).
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    expect(container.read(queueControllerProvider).repeatMode, RepeatMode.all);
    expect(sink.calls, contains('repeat(all)'));

    // All → one: the glyph switches to the repeat_one variant.
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    expect(container.read(queueControllerProvider).repeatMode, RepeatMode.one);
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);
    expect(sink.calls, contains('repeat(one)'));
  });

  testWidgets('the toolbar exposes Like, Queue, Lyrics, A-B and an overflow',
      (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    final ProviderContainer container = _container(sink);
    addTearDown(container.dispose);

    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('a')]);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget); // Like
    expect(find.byIcon(Icons.queue_music), findsOneWidget); // Queue
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget); // Lyrics
    expect(find.byIcon(Icons.repeat_on_outlined), findsOneWidget); // A-B
    expect(find.byIcon(Icons.more_vert), findsOneWidget); // overflow
  });
}
