import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/state/database_providers.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/theme_providers.dart';

/// A [LibraryScan] whose state we can flip in-test, to prove the artist-artwork
/// cache recomputes when a scan completes.
class _TestScan extends LibraryScan {
  @override
  LibraryScanState build() => const LibraryScanIdle();

  void markDone() => state = const LibraryScanDone(
        ScanSummary(
          tracks: 1,
          deleted: 0,
          errors: 0,
          repaired: 0,
          elapsed: Duration.zero,
        ),
      );
}

Future<void> _seedArtistWithArt(VibyDatabase db) async {
  await db.libraryDao.upsertArtists(<ArtistsCompanion>[
    ArtistsCompanion.insert(id: 'artist:ts', name: 'Travis Scott'),
  ]);
  await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
    AlbumsCompanion.insert(
        id: 'album:astro', name: 'ASTROWORLD', artistId: 'artist:ts'),
  ]);
  await db.libraryDao.upsertTracks(<TracksCompanion>[
    TracksCompanion.insert(
      id: 't1',
      source: TrackSource.local,
      title: 't1',
      albumId: 'album:astro',
      artistId: 'artist:ts',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    ),
  ]);
  await db.libraryDao.setAlbumArtwork('album:astro', 'art:astro');
}

ProviderContainer _container(VibyDatabase db, {LibraryScan Function()? scan}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      vibyDatabaseProvider.overrideWithValue(db),
      artworkDirectoryProvider.overrideWith(
        (Ref ref) => Future<Directory>.value(Directory.systemTemp),
      ),
      if (scan != null) libraryScanProvider.overrideWith(scan),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late VibyDatabase db;
  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'artistSeed reuses the shared palette cache — a seed persisted for the '
      "derived artwork is returned without re-extraction", () async {
    await _seedArtistWithArt(db);
    // Pre-populate the SAME drift palette cache the dynamic-theme pipeline uses,
    // keyed by the derived album's artwork key. No image file exists in the temp
    // dir, so on-the-fly extraction would return null — only a cache hit yields
    // this colour.
    const int seedArgb = 0xFF3366CC;
    await db.paletteDao.putSeed('art:astro', seedArgb);

    final ProviderContainer container = _container(db);
    final Color? seed =
        await container.read(artistSeedProvider('artist:ts').future);

    expect(seed, isNotNull);
    expect(seed!.toARGB32(), seedArgb);
  });

  test('artistSeed is null for an artist with no derived art', () async {
    await db.libraryDao.upsertArtists(<ArtistsCompanion>[
      ArtistsCompanion.insert(id: 'artist:na', name: 'No Art'),
    ]);
    final ProviderContainer container = _container(db);
    expect(
      await container.read(artistSeedProvider('artist:na').future),
      isNull,
    );
  });

  test('artistArtwork recomputes when a scan completes (rescan invalidation)',
      () async {
    final ProviderContainer container =
        _container(db, scan: _TestScan.new);

    // No art yet → the portrait key is null.
    expect(
      await container.read(artistArtworkProvider('artist:ts').future),
      isNull,
    );

    // A scan finds and writes the artist's album art...
    await _seedArtistWithArt(db);
    // ...and completes: the scan-done signal must invalidate the one-shot cache.
    (container.read(libraryScanProvider.notifier) as _TestScan).markDone();
    await container.pump();

    expect(
      await container.read(artistArtworkProvider('artist:ts').future),
      'art:astro',
    );
  });
}
