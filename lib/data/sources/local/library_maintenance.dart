import 'dart:developer' as developer;

import '../../db/viby_database.dart';
import 'artwork_service.dart';

/// What a purge actually removed. Everything is a *set* so a caller can report
/// honestly ("Deleted 12 songs") and tests can assert the cascade.
class PurgeResult {
  const PurgeResult({
    this.tracks = 0,
    this.albums = const <String>{},
    this.artists = const <String>{},
    this.artworkKeys = const <String>{},
  });

  /// Tracks actually removed (0 when the ids were already gone — see the
  /// idempotency contract on [LibraryMaintenance.purgeTracks]).
  final int tracks;

  /// Albums deleted because their last track died.
  final Set<String> albums;

  /// Artists deleted because their last track/album died.
  final Set<String> artists;

  /// Artwork keys whose files + cached palettes were evicted.
  final Set<String> artworkKeys;

  bool get isEmpty => tracks == 0;
}

/// The ONE place tracks leave the library.
///
/// Both deletion paths funnel through [purgeTracks]:
/// * the user deleting files from the device ("Delete from device"), and
/// * the incremental scanner finding a track gone from MediaStore.
///
/// They are the same cleanup, so they share it rather than forking — which also
/// makes them safe to *race*: deleting a file makes the MediaStore observer fire
/// a rescan whose diff will name the same ids, and purging ids that are already
/// gone is a no-op ([PurgeResult.isEmpty]).
///
/// FKs cascade history / cache entries / lyrics away when a track row dies. What
/// they do NOT cover, and this does:
/// * playlist entries (`trackId` is a plain key) — dropped, positions re-compacted;
/// * album track counts — recomputed, and albums left with no tracks deleted;
/// * artists left with no tracks and no albums — deleted;
/// * artwork files + cached palette seeds no surviving row points at — evicted.
///
/// (Liked state and visibility need no cleanup: they are columns on the track
/// row and die with it.)
class LibraryMaintenance {
  LibraryMaintenance(this._db, {ArtworkEvictor? artwork}) : _artwork = artwork;

  final VibyDatabase _db;
  final ArtworkEvictor? _artwork;

  /// Removes [trackIds] and everything that dangles off them. Idempotent: ids
  /// that no longer exist are skipped, so a purge racing the observer-triggered
  /// rescan is harmless.
  ///
  /// DB work runs in one transaction; artwork files are deleted after it commits
  /// (never hold a write transaction open across file I/O), and a failed file
  /// delete never fails the purge.
  Future<PurgeResult> purgeTracks(List<String> trackIds) async {
    if (trackIds.isEmpty) return const PurgeResult();

    PurgeResult result = const PurgeResult();
    await _db.transaction(() async {
      final List<TrackRow> rows =
          await _db.libraryDao.trackRowsByIds(trackIds);
      if (rows.isEmpty) return; // already purged — nothing to do

      final List<String> ids = rows.map((TrackRow r) => r.id).toList();
      final Set<String> albumIds = rows.map((TrackRow r) => r.albumId).toSet();
      final Set<String> artistIds = rows.map((TrackRow r) => r.artistId).toSet();

      await _db.playlistDao.removeTracksFromAllPlaylists(ids);
      await _db.libraryDao.deleteTracks(ids); // cascades history/cache/lyrics
      await _db.libraryDao.recomputeAlbumTrackCounts(albumIds);

      final List<AlbumRow> dead = await _db.libraryDao.emptyAlbums(albumIds);
      final Set<String> deadAlbumIds =
          dead.map((AlbumRow a) => a.id).toSet();
      final Set<String> candidateArt = <String>{
        for (final AlbumRow a in dead)
          if (a.artworkKey != null) a.artworkKey!,
        for (final TrackRow t in rows)
          if (t.artworkKey != null) t.artworkKey!,
      };
      await _db.libraryDao.deleteAlbums(deadAlbumIds.toList());

      final List<String> deadArtists =
          await _db.libraryDao.emptyArtists(artistIds);
      await _db.libraryDao.deleteArtists(deadArtists);

      // Orphan check runs AFTER the deletes, so a key still referenced by a
      // surviving track/album is correctly kept.
      final List<String> orphanedArt =
          await _db.libraryDao.orphanedArtworkKeys(candidateArt);
      await _db.paletteDao.deleteSeeds(orphanedArt);

      result = PurgeResult(
        tracks: ids.length,
        albums: deadAlbumIds,
        artists: deadArtists.toSet(),
        artworkKeys: orphanedArt.toSet(),
      );
    });

    for (final String key in result.artworkKeys) {
      try {
        await _artwork?.evictArtwork(key);
      } catch (error) {
        // A stuck art file is cosmetic — never fail a purge over it.
        developer.log(
          'artwork evict failed for $key',
          name: 'viby.maintenance',
          error: error,
        );
      }
    }

    if (!result.isEmpty) {
      developer.log(
        'purged ${result.tracks} tracks, ${result.albums.length} albums, '
        '${result.artists.length} artists, ${result.artworkKeys.length} artworks',
        name: 'viby.maintenance',
      );
    }
    return result;
  }
}
