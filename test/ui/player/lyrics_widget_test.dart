import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/ui/player/lyrics_peek.dart';
import 'package:viby/ui/widgets/shimmer.dart';

Lyrics _synced(List<int> starts) => Lyrics(
      lines: starts
          .map((int ms) => LyricLine(startMs: ms, text: 'line${starts.indexOf(ms)}'))
          .toList(),
      isSynced: true,
      source: LyricsSource.sidecarLrc,
    );

/// A fake settings notifier that skips DB hydration so peek tests can pin the
/// online-enabled flag without a database override.
class _FakeOnlineSettings extends OnlineLyricsSettings {
  _FakeOnlineSettings(this._value);
  final OnlineLyricsState _value;
  @override
  OnlineLyricsState build() => _value;
}

Override _online({required bool enabled}) =>
    onlineLyricsSettingsProvider.overrideWith(() => _FakeOnlineSettings(
          OnlineLyricsState(enabled: enabled, wifiOnly: false),
        ));

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('peek is hidden when there are no lyrics and online is off',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider.overrideWith((ref) async => const Lyrics.none()),
          _online(enabled: false),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pumpAndSettle();
    // No peek chrome rendered (reflows to zero size).
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
  });

  testWidgets(
      'peek offers "Search for lyrics" when empty and online is enabled',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider.overrideWith((ref) async => const Lyrics.none()),
          _online(enabled: true),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.text('Search for lyrics'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('peek shows a shimmer (never a spinner) while a fetch is in flight',
      (tester) async {
    final Completer<Lyrics> pending = Completer<Lyrics>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const Lyrics.none());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider.overrideWith((ref) => pending.future),
          _online(enabled: true),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pump(); // resolve the first frame; future still pending

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
  });

  testWidgets('peek shows an Instrumental affordance', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider
              .overrideWith((ref) async => const Lyrics.instrumental()),
          _online(enabled: true),
        ],
        child: _host(LyricsPeek(onExpand: () {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Instrumental'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
  });

  testWidgets('peek shows the current synced line', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          currentLyricsProvider
              .overrideWith((ref) async => _synced(<int>[1000, 3000, 7000])),
          lyricsActiveIndexProvider.overrideWith((ref) => 1),
          _online(enabled: true),
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
