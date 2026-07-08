import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/widgets/stagger.dart';

/// Finds the reduced-opacity wrapper (if any) around [key]. Returns 1.0 when the
/// entrance has finished (it then renders the child directly, no Opacity).
double _entranceOpacity(WidgetTester tester, Key key) {
  final Finder f = find.ancestor(
    of: find.byKey(key),
    matching: find.byType(Opacity),
  );
  if (f.evaluate().isEmpty) return 1.0;
  return tester.widget<Opacity>(f.first).opacity;
}

Widget _harness(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: StaggerScope(child: child),
    );

void main() {
  testWidgets('entrance animates in on first mount, then settles', (
    WidgetTester tester,
  ) async {
    const Key k = Key('cell');
    await tester.pumpWidget(
      _harness(const StaggeredEntrance(index: 0, child: SizedBox(key: k))),
    );

    // At mount the shared controller is at 0 → the item starts hidden.
    expect(_entranceOpacity(tester, k), lessThan(1.0));

    await tester.pumpAndSettle();

    // Once finished it renders fully (and without an Opacity wrapper at all).
    expect(_entranceOpacity(tester, k), 1.0);
  });

  testWidgets('does not re-trigger on rebuild (once per tab visit)', (
    WidgetTester tester,
  ) async {
    const Key k = Key('cell');
    final ValueNotifier<int> rebuilds = ValueNotifier<int>(0);
    addTearDown(rebuilds.dispose);

    await tester.pumpWidget(
      _harness(
        ValueListenableBuilder<int>(
          valueListenable: rebuilds,
          builder: (BuildContext context, int value, _) => const StaggeredEntrance(
            index: 0,
            child: SizedBox(key: k, width: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_entranceOpacity(tester, k), 1.0);

    // Force a rebuild of the entrance's subtree; it must NOT start hiding again.
    rebuilds.value++;
    await tester.pump();
    expect(_entranceOpacity(tester, k), 1.0);
  });
}
