import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/theme/app_theme.dart';
import 'package:viby/ui/theme/theme_collection.dart';
import 'package:viby/ui/widgets/pro_badge.dart';
import 'package:viby/ui/widgets/theme_preview_card.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders the theme name and fires onTap', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(_host(ThemePreviewCard(
      theme: midnightAurora,
      selected: false,
      onTap: () => tapped = true,
    )));
    await tester.pump();

    expect(find.text('Midnight Aurora'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector));
    expect(tapped, isTrue);
  });

  testWidgets('Pro themes show the PRO badge; Classic does not',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(ThemePreviewCard(
      theme: nebula,
      selected: false,
      onTap: () {},
    )));
    await tester.pump();
    expect(find.byType(ProBadge), findsOneWidget);

    await tester.pumpWidget(_host(ThemePreviewCard(
      theme: classicDark,
      selected: false,
      onTap: () {},
    )));
    await tester.pump();
    expect(find.byType(ProBadge), findsNothing);
  });

  testWidgets('selected card shows the check indicator',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(ThemePreviewCard(
      theme: frost,
      selected: true,
      onTap: () {},
    )));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
