import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/artist_art.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';

/// Regression: `artistArtCandidates` used to read its `trackCount`/`playCount`
/// aggregates without adding them to the joined statement — which throws in
/// drift, so the whole query failed for *every* artist and the artwork provider
/// fell back to the letter avatar everywhere. These tests seed real album art
/// and assert the candidates come back (and the picker falls through play-count).

TracksCompanion _track(String id,
        {required String album, required String artist}) =>
    TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: album,
      artistId: artist,
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  late VibyDatabase db;
  setUp(() => db = VibyDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Travis-like artist: three albums, all with art, but NO plays.
  Future<void> seedArtistWithArtNoPlays() async {
    await db.libraryDao.upsertArtists(<ArtistsCompanion>[
      ArtistsCompanion.insert(id: 'artist:ts', name: 'Travis Scott'),
    ]);
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(
          id: 'album:astroworld', name: 'ASTROWORLD', artistId: 'artist:ts'),
      AlbumsCompanion.insert(
          id: 'album:birds', name: 'Birds', artistId: 'artist:ts'),
      AlbumsCompanion.insert(
          id: 'album:highest', name: 'Highest', artistId: 'artist:ts'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('t1', album: 'album:astroworld', artist: 'artist:ts'),
      _track('t2', album: 'album:birds', artist: 'artist:ts'),
      _track('t3', album: 'album:highest', artist: 'artist:ts'),
    ]);
    // Every album has artwork.
    await db.libraryDao.setAlbumArtwork('album:astroworld', 'art:astroworld');
    await db.libraryDao.setAlbumArtwork('album:birds', 'art:birds');
    await db.libraryDao.setAlbumArtwork('album:highest', 'art:highest');
  }

  test(
      'candidates come back for an artist whose albums have art but zero plays '
      '(the query must not throw on its aggregates)', () async {
    await seedArtistWithArtNoPlays();

    final List<ArtistArtCandidate> candidates =
        await db.libraryDao.artistArtCandidates('artist:ts');

    expect(candidates, hasLength(3));
    expect(
      candidates.every((ArtistArtCandidate c) => c.artworkKey != null),
      isTrue,
    );
    // The whole point: the fallback chain falls THROUGH to album art even with
    // no play history — the picker returns a real key, not null.
    expect(pickArtistArtworkKey(candidates), isNotNull);
  });

  test('play count wins: the most-played album becomes the portrait', () async {
    await seedArtistWithArtNoPlays();
    // Give "Birds" the most plays; "Highest" one.
    await db.historyDao.recordPlay(trackId: 't2');
    await db.historyDao.recordPlay(trackId: 't2');
    await db.historyDao.recordPlay(trackId: 't3');

    final List<ArtistArtCandidate> candidates =
        await db.libraryDao.artistArtCandidates('artist:ts');
    final ArtistArtCandidate birds =
        candidates.firstWhere((ArtistArtCandidate c) => c.albumId == 'album:birds');
    expect(birds.playCount, 2);
    expect(pickArtistArtworkKey(candidates), 'art:birds');
  });

  test('an artist with no album art yields null (→ letter avatar)', () async {
    await db.libraryDao.upsertArtists(<ArtistsCompanion>[
      ArtistsCompanion.insert(id: 'artist:none', name: 'No Art'),
    ]);
    await db.libraryDao.upsertAlbums(<AlbumsCompanion>[
      AlbumsCompanion.insert(
          id: 'album:na', name: 'NA', artistId: 'artist:none'),
    ]);
    await db.libraryDao.upsertTracks(<TracksCompanion>[
      _track('n1', album: 'album:na', artist: 'artist:none'),
    ]);

    final List<ArtistArtCandidate> candidates =
        await db.libraryDao.artistArtCandidates('artist:none');
    expect(candidates, hasLength(1));
    expect(pickArtistArtworkKey(candidates), isNull);
  });
}
