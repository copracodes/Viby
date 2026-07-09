import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/theme/app_theme.dart';

/// The transparent scaffolds of Step 3.2 can't use the default zoom transition
/// (it snapshots transparent pixels to black, then ghosts two transparent
/// routes when snapshotting is off). The theme installs a fade-through builder
/// on the mobile platforms instead; these tests pin that wiring and its
/// no-black / no-ghost behaviour.
void main() {
  group('page transitions over transparent scaffolds', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      test('a fade-through builder is registered for $platform', () {
        final ThemeData theme = AppTheme.dark();
        final PageTransitionsBuilder? builder =
            theme.pageTransitionsTheme.builders[platform];
        expect(builder, isNotNull);
        // The default builders are Zoom (android) / Cupertino (iOS); ours is
        // neither, so a change back to those trips this test.
        expect(builder, isNot(isA<ZoomPageTransitionsBuilder>()));
        expect(builder, isNot(isA<CupertinoPageTransitionsBuilder>()));
      });
    }

    testWidgets('push fades content through the shared background (no black)',
        (WidgetTester tester) async {
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.dark(),
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('detail'))),
        ),
      );

      // Mid-transition: the fade-through wraps route content in FadeTransitions,
      // and both routes stay transparent (the shared AppBackground shows through
      // rather than a black snapshot).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(FadeTransition), findsWidgets);

      // Settle: the incoming route is fully visible, the outgoing is gone.
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    });
  });
}
