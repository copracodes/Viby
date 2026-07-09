import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/tables.dart' show TrackSource, TrackVisibility;
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/models/track.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/queue_provider.dart';
import 'package:viby/ui/screens/album_detail_screen.dart';
import 'package:viby/ui/screens/library_screen.dart';
import 'package:viby/ui/theme/app_theme.dart';

import '../support/fake_queue_sink.dart';

// Fake DAO rows — the album screens are driven by provider overrides so the
// widget tests never touch a real (async) drift stream.
const AlbumRow _album = AlbumRow(
  id: 'album:1',
  name: 'Greatest',
  artistId: 'artist:1',
  year: 2020,
  trackCount: 2,
);

const ArtistRow _artist = ArtistRow(id: 'artist:1', name: 'The Band');

TrackRow _track(String id, String title, int trackNo) => TrackRow(
      id: id,
      source: TrackSource.local,
      title: title,
      albumId: 'album:1',
      artistId: 'artist:1',
      trackNo: trackNo,
      discNo: 0,
      durationMs: 180000,
      filePath: '/music/$id.mp3',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
      playable: true,
      visibility: TrackVisibility.visible,
      userOverride: false,
      liked: false,
    );

final List<TrackRow> _tracks = <TrackRow>[
  _track('local:1', 'One', 1),
  _track('local:2', 'Two', 2),
];

Override _artworkOverride() => artworkDirectoryProvider.overrideWith(
      (Ref ref) => Future<Directory>.value(Directory.systemTemp),
    );

void main() {
  testWidgets('albums grid renders album name and artist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _artworkOverride(),
          albumsProvider.overrideWith(
            (Ref ref) => Stream<List<AlbumWithArtist>>.value(
              <AlbumWithArtist>[
                const AlbumWithArtist(album: _album, artistName: 'The Band'),
              ],
            ),
          ),
          artistsProvider.overrideWith(
            (Ref ref) => Stream<List<ArtistRow>>.value(const <ArtistRow>[]),
          ),
          allTracksProvider.overrideWith(
            (Ref ref) => Stream<List<TrackWithMeta>>.value(
              const <TrackWithMeta>[],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Greatest'), findsOneWidget);
    expect(find.text('The Band'), findsWidgets);
  });

  testWidgets('album detail Play button queues the whole album', (
    WidgetTester tester,
  ) async {
    final FakeSink sink = FakeSink();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _artworkOverride(),
          queueSinkProvider.overrideWithValue(sink),
          albumDetailProvider('album:1').overrideWith(
            (Ref ref) => Stream<AlbumWithTracks?>.value(
              AlbumWithTracks(album: _album, tracks: _tracks),
            ),
          ),
          artistProvider('artist:1').overrideWith(
            (Ref ref) => Stream<ArtistRow?>.value(_artist),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AlbumDetailScreen(albumId: 'album:1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(
      sink.lastLoaded.map((Track t) => t.id).toList(),
      <String>['local:1', 'local:2'],
    );
    expect(sink.lastInitialIndex, 0);
    expect(sink.lastAutoPlay, isTrue);
  });

  testWidgets('tapping a track row plays the album from that track', (
    WidgetTester tester,
  ) async {
    final FakeSink sink = FakeSink();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _artworkOverride(),
          queueSinkProvider.overrideWithValue(sink),
          albumDetailProvider('album:1').overrideWith(
            (Ref ref) => Stream<AlbumWithTracks?>.value(
              AlbumWithTracks(album: _album, tracks: _tracks),
            ),
          ),
          artistProvider('artist:1').overrideWith(
            (Ref ref) => Stream<ArtistRow?>.value(_artist),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AlbumDetailScreen(albumId: 'album:1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();

    expect(sink.lastInitialIndex, 1);
    expect(
      sink.lastLoaded.map((Track t) => t.id).toList(),
      <String>['local:1', 'local:2'],
    );
  });
}
