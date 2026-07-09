// Regression: Library (a TabBarView with a flingable Tracks list) must stay
// stable under the Step 3.2 theme wiring — no "setState() during build" from the
// TabBar/TabBarController machinery when scrolling or when a theme morph
// animates over it (the _TabStyle collision seen on-device).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/app.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/daos/playlist_dao.dart';
import 'package:viby/data/db/tables.dart' show TrackSource, TrackVisibility;
import 'package:viby/data/db/viby_database.dart' show ArtistRow, TrackRow;
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/playlist_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/state/theme_providers.dart';

import '../support/fake_queue_sink.dart';

TrackWithMeta _meta(int i) => TrackWithMeta(
      track: TrackRow(
        id: 'local:$i',
        source: TrackSource.local,
        title: 'Track $i',
        albumId: 'album:1',
        artistId: 'artist:1',
        trackNo: i,
        discNo: 0,
        durationMs: 180000,
        filePath: '/music/$i.mp3',
        dateAdded: DateTime(2026),
        dateModified: DateTime(2026),
        playable: true,
        visibility: TrackVisibility.visible,
        userOverride: false,
        liked: false,
      ),
      albumName: 'Album',
      artistName: 'Artist',
    );

void main() {
  testWidgets('Library Tracks fling + theme morph stays stable',
      (WidgetTester tester) async {
    final List<TrackWithMeta> tracks =
        List<TrackWithMeta>.generate(80, _meta);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          queueSinkProvider.overrideWithValue(FakeSink()),
          playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
          libraryTrackCountProvider
              .overrideWith((Ref ref) => Stream<int>.value(tracks.length)),
          albumsProvider.overrideWith((Ref ref) =>
              Stream<List<AlbumWithArtist>>.value(const <AlbumWithArtist>[])),
          artistsProvider.overrideWith(
              (Ref ref) => Stream<List<ArtistRow>>.value(const <ArtistRow>[])),
          allTracksProvider
              .overrideWith((Ref ref) => Stream<List<TrackWithMeta>>.value(tracks)),
          playlistSummariesProvider.overrideWith((Ref ref) =>
              Stream<List<PlaylistSummary>>.value(const <PlaylistSummary>[])),
        ],
        child: const VibyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(VibyApp)));

    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();

    // Fling the populated list while a theme morph animates over it.
    container.read(themeSettingsProvider.notifier).selectTheme('midnight_aurora');
    await tester.pump();
    await tester.fling(find.text('Track 1'), const Offset(0, -600), 4000);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.fling(find.byType(Scrollable).last, const Offset(0, 800), 4000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
