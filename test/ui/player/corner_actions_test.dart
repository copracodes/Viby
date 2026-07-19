import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/state/ab_loop_provider.dart';
import 'package:viby/state/database_providers.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/player/ab_repeat_icon.dart';
import 'package:viby/ui/player/player_progress_row.dart';
import 'package:viby/ui/widgets/like_button.dart';

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

Future<void> _pumpRow(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ProgressWithActions(trackId: 'Song One', onOpenQueue: () {}),
        ),
      ),
    ),
  );
  await container
      .read(queueControllerProvider.notifier)
      .setQueue(<Track>[_t('Song One')]);
  await tester.pumpAndSettle();
}

ProviderContainer _container() {
  final VibyDatabase db = VibyDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      vibyDatabaseProvider.overrideWithValue(db),
      queueSinkProvider.overrideWithValue(FakeSink()),
      positionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
      bufferedPositionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
      trackDurationProvider.overrideWith(
        (Ref ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
      ),
      currentLyricsProvider.overrideWith((Ref ref) async => const Lyrics.none()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets(
      'the four corner actions are one plain-glyph family at 24dp — the A-B '
      'mark is the custom glyph, NOT the background-container repeat_on icon',
      (WidgetTester tester) async {
    await _pumpRow(tester, _container());

    // A-B uses the custom glyph; the old chip-background icon is gone entirely.
    expect(find.byType(AbRepeatIcon), findsOneWidget);
    expect(find.byIcon(Icons.repeat_on_outlined), findsNothing);
    expect(find.byIcon(Icons.repeat_on), findsNothing);

    // The family: heart, queue and more are plain glyphs, all present.
    expect(find.byType(LikeButton), findsOneWidget);
    expect(find.byIcon(Icons.queue_music), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // Every corner glyph is 24dp (the bump from 20dp), touch targets ≥ 44dp.
    for (final IconButton button
        in tester.widgetList<IconButton>(find.byType(IconButton))) {
      if (button.iconSize != null) {
        expect(button.iconSize, 24, reason: 'corner icons should be 24dp');
      }
    }
    final AbRepeatIcon ab = tester.widget(find.byType(AbRepeatIcon));
    expect(ab.size, 24);
  });

  testWidgets('the A-B glyph turns primary (color+fill only) when armed',
      (WidgetTester tester) async {
    final ProviderContainer container = _container();
    await _pumpRow(tester, container);

    final BuildContext ctx = tester.element(find.byType(ProgressWithActions));
    final Color primary = Theme.of(ctx).colorScheme.primary;
    final Color inactive = Theme.of(ctx).colorScheme.onSurfaceVariant;

    // Inactive: secondary colour.
    AbRepeatIcon ab = tester.widget(find.byType(AbRepeatIcon));
    expect(ab.color, inactive);

    // Arm A–B (two taps: set A, then set B) and the glyph goes primary.
    final AbLoopController controller =
        container.read(abLoopControllerProvider.notifier);
    controller.tap();
    controller.tap();
    await tester.pump();

    ab = tester.widget(find.byType(AbRepeatIcon));
    expect(ab.color, primary);
  });
}
