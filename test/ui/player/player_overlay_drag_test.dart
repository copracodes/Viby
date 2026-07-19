import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/state/database_providers.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/player/player_overlay.dart';

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

/// Builds the overlay with one track loaded and returns the container.
Future<ProviderContainer> _pumpOverlay(WidgetTester tester) async {
  final StreamController<bool> playing = StreamController<bool>.broadcast();
  addTearDown(playing.close);
  final VibyDatabase db = VibyDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      vibyDatabaseProvider.overrideWithValue(db),
      queueSinkProvider.overrideWithValue(FakeSink()),
      // Never "playing": keeps the equalizer indicator (which animates forever)
      // out of the tree so pumpAndSettle terminates.
      playingProvider.overrideWith((Ref ref) => playing.stream),
      positionProvider
          .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
      trackDurationProvider.overrideWith(
        (Ref ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
      ),
      artworkDirectoryProvider.overrideWith(
        (Ref ref) => Future<Directory>.value(Directory.systemTemp),
      ),
      // Resolve lyrics to "none" instantly so the peek never sits in its
      // shimmer-loading state (which would animate forever under pumpAndSettle).
      currentLyricsProvider
          .overrideWith((Ref ref) async => const Lyrics.none()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlayerOverlay())),
    ),
  );
  await container
      .read(queueControllerProvider.notifier)
      .setQueue(<Track>[_t('Song One')]);
  await tester.pumpAndSettle();
  return container;
}

/// Expands the overlay to full Now Playing by tapping the mini bar strip.
Future<void> _expand(WidgetTester tester) async {
  // The collapsed panel occupies the mini strip near the bottom; tap it.
  final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width / 2, size.height - 110));
  await tester.pumpAndSettle();
  // Sanity: the full layout's collapse chevron is present when expanded.
  expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget,
      reason: 'overlay should be fully expanded before the collapse drag');
}

/// Drags down from [start] by [totalDown] pixels at a *moderate* velocity
/// (below the fling threshold), pumping each frame so `artInteractive` is
/// recomputed exactly as it is on device.
Future<void> _dragDown(
  WidgetTester tester,
  Offset start, {
  double totalDown = 260,
  int steps = 13,
}) async {
  final TestGesture gesture = await tester.startGesture(start);
  final double per = totalDown / steps;
  for (int i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, per));
    // ~50ms/frame → ~per*20 px/s, a moderate (non-fling) release velocity.
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a single moderate drag down from the ARTWORK minimizes full → mini '
      '(regression: origin flip + artwork recognizer disposal)',
      (WidgetTester tester) async {
    await _pumpOverlay(tester);
    await _expand(tester);

    // Start the drag on the artwork (upper-middle of the screen). This exercises
    // both root causes at once: the artwork layer must keep its drag recognizer
    // as `t` falls past 0.98, and the settle must use the drag's *origin* (full),
    // not the release value (which is < 0.5 after crossing the midpoint).
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await _dragDown(tester, Offset(size.width / 2, size.height * 0.28));

    // Collapsed in ONE drag: the mini controls are back, the full chevron is gone.
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets(
      'a single moderate drag down from a bare panel area also minimizes',
      (WidgetTester tester) async {
    await _pumpOverlay(tester);
    await _expand(tester);

    // Start well left of the artwork column, mid-height: this lands on the bare
    // panel gesture surface (no interactive control), the "works from anywhere"
    // acceptance point.
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await _dragDown(tester, Offset(24, size.height * 0.28));

    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });
}
