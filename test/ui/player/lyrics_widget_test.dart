import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/ui/player/lyrics_peek.dart';

Lyrics _synced(List<int> starts) => Lyrics(
      lines: starts
          .map((int ms) => LyricLine(startMs: ms, text: 'line${starts.indexOf(ms)}'))
          .toList(),
      isSynced: true,
      source: LyricsSource.sidecarLrc,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('peek is hidden entirely when there are no lyrics', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider.overrideWith((ref) async => const Lyrics.none()),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pumpAndSettle();
    // No peek chrome rendered (reflows to zero size).
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
  });

  testWidgets('peek shows the current synced line', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider
              .overrideWith((ref) async => _synced(<int>[1000, 3000, 7000])),
          lyricsActiveIndexProvider.overrideWith((ref) => 1),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.text('line1'), findsOneWidget); // active line
  });

  testWidgets(
      'position ticks within a line do NOT rebuild the active-index consumer',
      (tester) async {
    final StreamController<Duration> pos = StreamController<Duration>();
    addTearDown(pos.close);
    int builds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider
              .overrideWith((ref) async => _synced(<int>[1000, 3000, 7000])),
          positionProvider.overrideWith((ref) => pos.stream),
        ],
        child: _host(
          Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(lyricsActiveIndexProvider);
              builds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final int baseline = builds; // initial build(s), activeIndex == -1

    // -1 (before first) → still -1 → no rebuild.
    pos.add(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(builds, baseline);

    // Crosses into line 0 → one rebuild.
    pos.add(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(builds, baseline + 1);

    // Still line 0 → no further rebuild despite the tick.
    pos.add(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(builds, baseline + 1);
  });
}
