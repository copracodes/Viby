import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/player/now_playing_backdrop.dart';

/// The queue state shares this one backdrop (Step 2.2 iteration bug #4): it must
/// be theme-reactive so a track change morphs the backdrop tint, not just the
/// accent. Guard that the backdrop's scheme-tinted layers recolour when the
/// ambient scheme changes.
List<Color> _backdropColors(WidgetTester tester) => tester
    .widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(NowPlayingBackdrop),
        matching: find.byType(ColoredBox),
      ),
    )
    .map((ColoredBox b) => b.color)
    .toList();

void main() {
  testWidgets('backdrop recolours when the scheme changes (theme-follow)',
      (WidgetTester tester) async {
    final ValueNotifier<Color> surface =
        ValueNotifier<Color>(const Color(0xFF101828));
    addTearDown(surface.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<Color>(
              valueListenable: surface,
              builder: (BuildContext context, Color s, _) => Theme(
                data: ThemeData(
                  colorScheme:
                      ColorScheme.fromSeed(seedColor: Colors.purple, surface: s),
                ),
                child: const NowPlayingBackdrop(artworkKey: null),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final List<Color> before = _backdropColors(tester);
    expect(before, isNotEmpty);

    surface.value = const Color(0xFF7A6050);
    await tester.pump();
    final List<Color> after = _backdropColors(tester);

    expect(after, isNot(equals(before)),
        reason: 'backdrop layers should recolour with the scheme');
  });
}
