// Smoke test: the app boots into the shell (bottom nav) and, with an empty
// library, lands on Home showing the scan call-to-action.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/app.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';

import 'support/fake_queue_sink.dart';

void main() {
  testWidgets('app boots to the shell with its nav destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // Playback wiring the shell/mini-player/history recorder touch.
          queueSinkProvider.overrideWithValue(FakeSink()),
          playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
          // Empty library → Home shows the scan CTA (no DB access in the test).
          libraryTrackCountProvider
              .overrideWith((Ref ref) => Stream<int>.value(0)),
        ],
        child: const VibyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home app bar + all four bottom-nav destinations.
    expect(find.text('Viby'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    // Empty-library call-to-action.
    expect(find.text('Scan library'), findsOneWidget);
  });
}
