// Smoke test: the app boots and lands on the placeholder home screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/app.dart';

void main() {
  testWidgets('app boots to the placeholder home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: VibyApp()));
    await tester.pumpAndSettle();

    // The home route renders and shows the app name.
    expect(find.text('Viby'), findsWidgets);
    expect(find.text('Scaffold ready.'), findsOneWidget);
  });
}
