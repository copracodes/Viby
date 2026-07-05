// Widget test: the play/pause button reflects playback state and flips its
// icon reactively when the `playing` provider changes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/ui/screens/home_screen.dart';

void main() {
  testWidgets('play button toggles its icon on playing-state change', (
    WidgetTester tester,
  ) async {
    final StreamController<bool> playing = StreamController<bool>.broadcast();
    addTearDown(playing.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          playingProvider.overrideWith((ref) => playing.stream),
          positionProvider
              .overrideWith((ref) => Stream<Duration>.value(Duration.zero)),
          trackDurationProvider.overrideWith(
            (ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    // Before any event the stream is loading → treated as paused → play icon.
    await tester.pump();
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle), findsNothing);

    // Playing starts → button shows pause.
    playing.add(true);
    await tester.pump();
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsNothing);

    // Paused again → button shows play.
    playing.add(false);
    await tester.pump();
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle), findsNothing);
  });
}
