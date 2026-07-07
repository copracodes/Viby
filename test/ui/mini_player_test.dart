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
      artistName: 'A Band',
      filePath: '/music/$id.mp3',
    );

void main() {
  testWidgets(
    'mini-player is hidden with an empty queue and appears once a track loads',
    (WidgetTester tester) async {
      final FakeSink sink = FakeSink();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          queueSinkProvider.overrideWithValue(sink),
          playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
          positionProvider
              .overrideWith((Ref ref) => Stream<Duration>.value(Duration.zero)),
          trackDurationProvider
              .overrideWith((Ref ref) => Stream<Duration?>.value(null)),
          artworkDirectoryProvider.overrideWith(
            (Ref ref) => Future<Directory>.value(Directory.systemTemp),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pumpAndSettle();

      // Empty queue → nothing rendered (no transport button).
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      // Load a queue → the mini-player shows the current track + play button.
      await container
          .read(queueControllerProvider.notifier)
          .setQueue(<Track>[_t('Song One')]);
      await tester.pumpAndSettle();

      expect(find.text('Song One'), findsOneWidget);
      expect(find.text('A Band'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    },
  );
}
