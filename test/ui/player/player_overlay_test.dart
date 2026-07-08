import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show TrackSource;
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/state/database_providers.dart';
import 'package:viby/state/library_providers.dart';
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

void main() {
  testWidgets(
      'overlay is empty with no queue, shows the mini bar once a track loads, '
      'and its play/pause icon tracks playing state',
      (WidgetTester tester) async {
    final StreamController<bool> playing = StreamController<bool>.broadcast();
    addTearDown(playing.close);
    final VibyDatabase db = VibyDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        vibyDatabaseProvider.overrideWithValue(db),
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerOverlay())),
      ),
    );
    await tester.pumpAndSettle();

    // Empty queue → nothing.
    expect(find.text('Song One'), findsNothing);

    // Load a track → the collapsed mini bar shows it, with a play button.
    await container
        .read(queueControllerProvider.notifier)
        .setQueue(<Track>[_t('Song One')]);
    await tester.pumpAndSettle();

    expect(find.text('Song One'), findsOneWidget);
    expect(find.text('A Band'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Playing state flips the icon. (Can't pumpAndSettle here: the now-visible
    // equalizer indicator animates forever.)
    playing.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}
