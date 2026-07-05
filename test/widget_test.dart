// Smoke test: the app boots and lands on the home screen with transport UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/app.dart';
import 'package:viby/state/player_providers.dart';

void main() {
  testWidgets('app boots to the home screen with a play button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          playingProvider.overrideWith((ref) => Stream<bool>.value(false)),
          positionProvider
              .overrideWith((ref) => Stream<Duration>.value(Duration.zero)),
          trackDurationProvider
              .overrideWith((ref) => Stream<Duration?>.value(null)),
        ],
        child: const VibyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Branding survives and the transport renders in its paused state.
    expect(find.text('Viby'), findsWidgets);
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
  });
}
