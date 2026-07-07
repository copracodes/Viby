// Widget test: the mini-player's play/pause button flips its icon reactively
// when the `playing` provider changes.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/widgets/mini_player.dart';

import '../support/fake_queue_sink.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album',
      artistId: 'artist',
      filePath: '/music/$id.mp3',
    );

void main() {
  testWidgets('mini-player play/pause icon reflects playing state', (
    WidgetTester tester,
  ) async {
    final StreamController<bool> playing = StreamController<bool>.broadcast();
    addTearDown(playing.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        queueSinkProvider.overrideWithValue(FakeSink()),
        playingProvider.overrideWith((Ref ref) => playing.stream),
        positionProvider
            .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
        trackDurationProvider.overrideWith(
          (Ref ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
        ),
        artworkDirectoryProvider.overrideWith(
          (Ref ref) => Future<Directory>.value(Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A track is playing so the mini-player is visible.
    await container.read(queueControllerProvider.notifier).setQueue(<Track>[
      _t('a'),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
      ),
    );

    // No event yet → treated as paused → play icon.
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    playing.add(true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    playing.add(false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });
}
