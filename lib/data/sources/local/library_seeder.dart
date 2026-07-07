import 'package:drift/drift.dart';

import '../../db/daos/library_dao.dart';
import '../../db/tables.dart';
import '../../db/viby_database.dart';

/// The id marker for debug-seeded rows. Everything the seeder writes lives under
/// this prefix so "clear synthetic" can remove exactly it and nothing real.
const String kSyntheticPrefix = 'local:synthetic:';

/// Seeds the library with synthetic tracks/albums/artists straight into drift —
/// no files, no permissions — so the UI can be exercised at scale (10k tracks).
///
/// Debug-only: invoked from Settings › Developer. All rows carry the
/// [kSyntheticPrefix] id marker; [LibraryDao.deleteSyntheticData] removes them.
class LibrarySeeder {
  LibrarySeeder(this._dao);

  final LibraryDao _dao;

  /// Inserts [tracks] synthetic tracks spread across [albums] albums and
  /// [artists] artists (defaults: 10k / 800 / 400). Reports [onProgress]
  /// (0..tracks) as it writes. Idempotent per id (upsert), so re-running with
  /// the same counts overwrites rather than duplicating.
  Future<void> seed({
    int tracks = 10000,
    int albums = 800,
    int artists = 400,
    int chunkSize = 1000,
    void Function(int written, int total)? onProgress,
  }) async {
    final DateTime now = DateTime.now();

    // Artists.
    final List<ArtistsCompanion> artistRows = <ArtistsCompanion>[
      for (int a = 0; a < artists; a++)
        ArtistsCompanion.insert(
          id: '${kSyntheticPrefix}artist:$a',
          name: 'Synthetic Artist ${a.toString().padLeft(3, '0')}',
        ),
    ];
    await _dao.upsertArtists(artistRows);

    // Albums (each mapped to an artist round-robin).
    final List<AlbumsCompanion> albumRows = <AlbumsCompanion>[
      for (int al = 0; al < albums; al++)
        AlbumsCompanion.insert(
          id: '${kSyntheticPrefix}album:$al',
          name: 'Synthetic Album ${al.toString().padLeft(3, '0')}',
          artistId: '${kSyntheticPrefix}artist:${al % artists}',
        ),
    ];
    await _dao.upsertAlbums(albumRows);

    // Tracks in chunks so a huge insert doesn't build one giant batch.
    int written = 0;
    final Set<String> affectedAlbums = <String>{};
    for (int start = 0; start < tracks; start += chunkSize) {
      final int end = (start + chunkSize) > tracks ? tracks : start + chunkSize;
      final List<TracksCompanion> chunk = <TracksCompanion>[];
      for (int i = start; i < end; i++) {
        final int albumIndex = i % albums;
        final String albumId = '${kSyntheticPrefix}album:$albumIndex';
        affectedAlbums.add(albumId);
        chunk.add(
          TracksCompanion.insert(
            id: '${kSyntheticPrefix}track:$i',
            source: TrackSource.local,
            title: 'Synthetic Track ${i.toString().padLeft(5, '0')}',
            albumId: albumId,
            artistId: '${kSyntheticPrefix}artist:${albumIndex % artists}',
            filePath: Value('/synthetic/track_$i.mp3'),
            trackNo: Value((i % 20) + 1),
            durationMs: Value(120000 + (i % 180) * 1000),
            dateAdded: now.subtract(Duration(minutes: i)),
            dateModified: now.subtract(Duration(minutes: i)),
          ),
        );
      }
      await _dao.upsertTracks(chunk);
      written += chunk.length;
      onProgress?.call(written, tracks);
    }
    await _dao.recomputeAlbumTrackCounts(affectedAlbums);
  }

  /// Removes every synthetic row. Returns the number of tracks deleted.
  Future<int> clear() => _dao.deleteSyntheticData();
}
