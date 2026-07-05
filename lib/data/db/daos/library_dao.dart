import 'package:drift/drift.dart';

import '../tables.dart';
import '../util/stream_combine.dart';
import '../viby_database.dart';

part 'library_dao.g.dart';

/// Ordering options for [LibraryDao.watchAllTracks].
enum TrackSortOrder {
  titleAsc,
  titleDesc,
  dateAddedDesc,
  dateAddedAsc,
  durationAsc,
  durationDesc,
}

/// A track plus its resolved album/artist names — the row shape returned by
/// [LibraryDao.searchTracks].
class TrackWithMeta {
  const TrackWithMeta({
    required this.track,
    this.albumName,
    this.artistName,
  });

  final TrackRow track;
  final String? albumName;
  final String? artistName;
}

/// An album with its tracks, ordered by disc then track number.
class AlbumWithTracks {
  const AlbumWithTracks({required this.album, required this.tracks});

  final AlbumRow album;
  final List<TrackRow> tracks;
}

/// An artist with their albums, ordered by name.
class ArtistWithAlbums {
  const ArtistWithAlbums({required this.artist, required this.albums});

  final ArtistRow artist;
  final List<AlbumRow> albums;
}

/// Reactive reads and idempotent (batch) writes for the core library:
/// tracks, albums and artists.
@DriftAccessor(tables: <Type>[Tracks, Albums, Artists])
class LibraryDao extends DatabaseAccessor<VibyDatabase>
    with _$LibraryDaoMixin {
  LibraryDao(super.db);

  // --- Albums -------------------------------------------------------------

  Stream<List<AlbumRow>> watchAllAlbums() {
    return (select(albums)
          ..orderBy(<OrderClauseGenerator<$AlbumsTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
  }

  /// Album + its tracks (disc, then track number). Null while the album id is
  /// unknown; re-emits as either side changes.
  Stream<AlbumWithTracks?> watchAlbumWithTracks(String albumId) {
    final Stream<AlbumRow?> albumStream =
        (select(albums)..where((t) => t.id.equals(albumId)))
            .watchSingleOrNull();
    final Stream<List<TrackRow>> tracksStream = (select(tracks)
          ..where((t) => t.albumId.equals(albumId))
          ..orderBy(<OrderClauseGenerator<$TracksTable>>[
            (t) => OrderingTerm(expression: t.discNo),
            (t) => OrderingTerm(expression: t.trackNo),
          ]))
        .watch();
    return combineLatest2<AlbumRow?, List<TrackRow>, AlbumWithTracks?>(
      albumStream,
      tracksStream,
      (AlbumRow? album, List<TrackRow> rows) =>
          album == null ? null : AlbumWithTracks(album: album, tracks: rows),
    );
  }

  // --- Artists ------------------------------------------------------------

  Stream<List<ArtistRow>> watchAllArtists() {
    return (select(artists)
          ..orderBy(<OrderClauseGenerator<$ArtistsTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
  }

  /// Artist + their albums (by name). Null while the artist id is unknown.
  Stream<ArtistWithAlbums?> watchArtistWithAlbums(String artistId) {
    final Stream<ArtistRow?> artistStream =
        (select(artists)..where((t) => t.id.equals(artistId)))
            .watchSingleOrNull();
    final Stream<List<AlbumRow>> albumsStream = (select(albums)
          ..where((t) => t.artistId.equals(artistId))
          ..orderBy(<OrderClauseGenerator<$AlbumsTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
    return combineLatest2<ArtistRow?, List<AlbumRow>, ArtistWithAlbums?>(
      artistStream,
      albumsStream,
      (ArtistRow? artist, List<AlbumRow> rows) => artist == null
          ? null
          : ArtistWithAlbums(artist: artist, albums: rows),
    );
  }

  // --- Tracks -------------------------------------------------------------

  Stream<List<TrackRow>> watchAllTracks(TrackSortOrder sort) {
    final SimpleSelectStatement<$TracksTable, TrackRow> query = select(tracks);
    switch (sort) {
      case TrackSortOrder.titleAsc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) => OrderingTerm(expression: t.title.lower()),
        ]);
      case TrackSortOrder.titleDesc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) => OrderingTerm(
            expression: t.title.lower(),
            mode: OrderingMode.desc,
          ),
        ]);
      case TrackSortOrder.dateAddedDesc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) =>
              OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc),
        ]);
      case TrackSortOrder.dateAddedAsc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) => OrderingTerm(expression: t.dateAdded),
        ]);
      case TrackSortOrder.durationAsc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) => OrderingTerm(expression: t.durationMs),
        ]);
      case TrackSortOrder.durationDesc:
        query.orderBy(<OrderClauseGenerator<$TracksTable>>[
          (t) =>
              OrderingTerm(expression: t.durationMs, mode: OrderingMode.desc),
        ]);
    }
    return query.watch();
  }

  /// Case-insensitive substring search across track title, album name and
  /// artist name. Left joins so a track with no matching album/artist row can
  /// still match on its title.
  Stream<List<TrackWithMeta>> searchTracks(String query) {
    final String pattern = '%${query.toLowerCase()}%';
    final JoinedSelectStatement<HasResultSet, dynamic> statement =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(albums, albums.id.equalsExp(tracks.albumId)),
          leftOuterJoin(artists, artists.id.equalsExp(tracks.artistId)),
        ])
          ..where(
            tracks.title.lower().like(pattern) |
                albums.name.lower().like(pattern) |
                artists.name.lower().like(pattern),
          )
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: tracks.title.lower()),
          ]);
    return statement.watch().map(
      (List<TypedResult> rows) => rows
          .map(
            (TypedResult row) => TrackWithMeta(
              track: row.readTable(tracks),
              albumName: row.readTableOrNull(albums)?.name,
              artistName: row.readTableOrNull(artists)?.name,
            ),
          )
          .toList(),
    );
  }

  // --- Writes (idempotent upserts for the scanner) ------------------------

  /// Idempotent batch upsert keyed by the deterministic `id`: re-scanning the
  /// same track updates it rather than duplicating.
  Future<void> upsertTracks(List<TracksCompanion> rows) {
    return batch((Batch b) => b.insertAllOnConflictUpdate(tracks, rows));
  }

  Future<void> upsertAlbums(List<AlbumsCompanion> rows) {
    return batch((Batch b) => b.insertAllOnConflictUpdate(albums, rows));
  }

  Future<void> upsertArtists(List<ArtistsCompanion> rows) {
    return batch((Batch b) => b.insertAllOnConflictUpdate(artists, rows));
  }

  Future<int> deleteTrack(String id) {
    return (delete(tracks)..where((t) => t.id.equals(id))).go();
  }
}
