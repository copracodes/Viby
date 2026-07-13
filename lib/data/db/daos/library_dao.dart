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

/// An album plus its resolved artist name — the row shape for the albums grid.
class AlbumWithArtist {
  const AlbumWithArtist({required this.album, this.artistName});

  final AlbumRow album;
  final String? artistName;
}

/// Reactive reads and idempotent (batch) writes for the core library:
/// tracks, albums and artists.
@DriftAccessor(tables: <Type>[Tracks, Albums, Artists])
class LibraryDao extends DatabaseAccessor<VibyDatabase>
    with _$LibraryDaoMixin {
  LibraryDao(super.db);

  // --- Visibility predicates ----------------------------------------------

  /// Whether an album still has at least one *visible* track.
  ///
  /// Hiding a track (junk filter or "Hide song") doesn't delete its album/artist
  /// rows — the scanner wrote them, and they must survive so the Hidden-songs
  /// screen can still resolve names. Without this predicate those rows show up in
  /// the library as empty ghost cards ("Alarms", "Call", an "Unknown artist" full
  /// of nothing). So browsing filters albums/artists the same way it filters
  /// tracks: an album exists in the library iff a visible track points at it.
  ///
  /// A correlated EXISTS rather than a join+group: it short-circuits on the first
  /// hit and rides the `idx_tracks_album` / `idx_tracks_artist` indexes, so it
  /// stays flat at 10k tracks (see `test/perf/scale_perf_test.dart`).
  Expression<bool> _albumHasVisibleTrack() => existsQuery(
        selectOnly(tracks)
          ..addColumns(<Expression<Object>>[tracks.id])
          ..where(tracks.albumId.equalsExp(albums.id) & _visible(tracks)),
      );

  /// Whether an artist still has at least one visible track (and so at least one
  /// non-ghost album).
  Expression<bool> _artistHasVisibleTrack() => existsQuery(
        selectOnly(tracks)
          ..addColumns(<Expression<Object>>[tracks.id])
          ..where(tracks.artistId.equalsExp(artists.id) & _visible(tracks)),
      );

  // --- Albums -------------------------------------------------------------

  Stream<List<AlbumRow>> watchAllAlbums() {
    return (select(albums)
          ..where((_) => _albumHasVisibleTrack())
          ..orderBy(<OrderClauseGenerator<$AlbumsTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
  }

  /// Every album with its artist name resolved (name order) — the albums grid.
  /// Ghost albums (all their tracks hidden) are excluded.
  Stream<List<AlbumWithArtist>> watchAlbumsWithArtist() {
    final JoinedSelectStatement<HasResultSet, dynamic> statement =
        select(albums).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(artists, artists.id.equalsExp(albums.artistId)),
        ])
          ..where(_albumHasVisibleTrack())
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: albums.name.lower()),
          ]);
    return statement.watch().map(
      (List<TypedResult> rows) => rows
          .map(
            (TypedResult r) => AlbumWithArtist(
              album: r.readTable(albums),
              artistName: r.readTableOrNull(artists)?.name,
            ),
          )
          .toList(),
    );
  }

  /// Predicate restricting a tracks query to library-visible rows. Applied to
  /// every track read path (album/artist/search/queue-restore/history/playlist)
  /// so junk-hidden and user-hidden tracks never surface in browsing.
  Expression<bool> _visible($TracksTable t) =>
      t.visibility.equalsValue(TrackVisibility.visible);

  /// Album + its tracks (disc, then track number). Null while the album id is
  /// unknown; re-emits as either side changes.
  Stream<AlbumWithTracks?> watchAlbumWithTracks(String albumId) {
    final Stream<AlbumRow?> albumStream =
        (select(albums)..where((t) => t.id.equals(albumId)))
            .watchSingleOrNull();
    final Stream<List<TrackRow>> tracksStream = (select(tracks)
          ..where((t) => t.albumId.equals(albumId) & _visible(t))
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

  /// Every artist with at least one visible track (name order) — the Artists tab.
  Stream<List<ArtistRow>> watchAllArtists() {
    return (select(artists)
          ..where((_) => _artistHasVisibleTrack())
          ..orderBy(<OrderClauseGenerator<$ArtistsTable>>[
            (t) => OrderingTerm(expression: t.name.lower()),
          ]))
        .watch();
  }

  /// A single artist row (for the album-detail header). Null while unknown.
  /// Deliberately UNfiltered — it resolves a name for a row we're already
  /// showing (including on the Hidden-songs screen), it doesn't list anything.
  Stream<ArtistRow?> watchArtist(String artistId) {
    return (select(artists)..where((t) => t.id.equals(artistId)))
        .watchSingleOrNull();
  }

  /// Artist + their albums (by name), ghost albums excluded. Null while the
  /// artist id is unknown.
  Stream<ArtistWithAlbums?> watchArtistWithAlbums(String artistId) {
    final Stream<ArtistRow?> artistStream =
        (select(artists)..where((t) => t.id.equals(artistId)))
            .watchSingleOrNull();
    final Stream<List<AlbumRow>> albumsStream = (select(albums)
          ..where((t) => t.artistId.equals(artistId) & _albumHasVisibleTrack())
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

  /// The most-recently-added tracks (dateAdded desc) — the Home strip.
  Stream<List<TrackRow>> watchRecentlyAdded({int limit = 20}) {
    return (select(tracks)
          ..where(_visible)
          ..orderBy(<OrderClauseGenerator<$TracksTable>>[
            (t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  /// Reactive count of *visible* tracks — drives library empty states.
  Stream<int> watchTrackCount() {
    final Expression<int> count = tracks.id.count();
    return (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[count])
          ..where(_visible(tracks)))
        .watchSingle()
        .map((TypedResult r) => r.read(count) ?? 0);
  }

  /// Reactive count of *hidden* tracks (user + filter) — drives the Tracks-tab
  /// "N hidden songs" footer.
  Stream<int> watchHiddenCount() {
    final Expression<int> count = tracks.id.count();
    return (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[count])
          ..where(_visible(tracks).not()))
        .watchSingle()
        .map((TypedResult r) => r.read(count) ?? 0);
  }

  Stream<List<TrackRow>> watchAllTracks(TrackSortOrder sort) {
    final SimpleSelectStatement<$TracksTable, TrackRow> query = select(tracks)
      ..where(_visible);
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
            (tracks.title.lower().like(pattern) |
                    albums.name.lower().like(pattern) |
                    artists.name.lower().like(pattern)) &
                _visible(tracks),
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

  /// One-shot fetch of specific tracks (+ resolved album/artist names) by id.
  /// Order is NOT guaranteed — callers re-order by their id list. This is a
  /// deliberate `get()` (not a `watch()`): it backs a one-time bootstrap
  /// (queue restore), not reactive list/detail UI.
  Future<List<TrackWithMeta>> getTracksByIds(List<String> ids) async {
    if (ids.isEmpty) return <TrackWithMeta>[];
    final JoinedSelectStatement<HasResultSet, dynamic> statement =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(albums, albums.id.equalsExp(tracks.albumId)),
          leftOuterJoin(artists, artists.id.equalsExp(tracks.artistId)),
        ])
          ..where(tracks.id.isIn(ids) & _visible(tracks));
    final List<TypedResult> rows = await statement.get();
    return rows
        .map(
          (TypedResult row) => TrackWithMeta(
            track: row.readTable(tracks),
            albumName: row.readTableOrNull(albums)?.name,
            artistName: row.readTableOrNull(artists)?.name,
          ),
        )
        .toList();
  }

  /// One-shot fetch of an artist's tracks (+ names), album/disc/track ordered.
  /// A deliberate `get()`: backs the "play all" action on artist detail, not a
  /// reactive list.
  Future<List<TrackWithMeta>> getTracksByArtist(String artistId) async {
    final JoinedSelectStatement<HasResultSet, dynamic> statement =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(albums, albums.id.equalsExp(tracks.albumId)),
          leftOuterJoin(artists, artists.id.equalsExp(tracks.artistId)),
        ])
          ..where(tracks.artistId.equals(artistId) & _visible(tracks))
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: albums.name.lower()),
            OrderingTerm(expression: tracks.discNo),
            OrderingTerm(expression: tracks.trackNo),
          ]);
    final List<TypedResult> rows = await statement.get();
    return rows
        .map(
          (TypedResult row) => TrackWithMeta(
            track: row.readTable(tracks),
            albumName: row.readTableOrNull(albums)?.name,
            artistName: row.readTableOrNull(artists)?.name,
          ),
        )
        .toList();
  }

  // --- Hidden + liked reads ----------------------------------------------

  /// Joined `select(tracks)` restricted to [where], newest-meaningful order
  /// supplied by [order]; shared by the hidden/liked screens.
  Stream<List<TrackWithMeta>> _watchTracksWhere(
    Expression<bool> where,
    List<OrderingTerm> order,
  ) {
    final JoinedSelectStatement<HasResultSet, dynamic> statement =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(albums, albums.id.equalsExp(tracks.albumId)),
          leftOuterJoin(artists, artists.id.equalsExp(tracks.artistId)),
        ])
          ..where(where)
          ..orderBy(order);
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

  /// Tracks the user hid via "Hide song" (title order) — Hidden-songs screen.
  Stream<List<TrackWithMeta>> watchHiddenByUser() => _watchTracksWhere(
        tracks.visibility.equalsValue(TrackVisibility.hiddenByUser),
        <OrderingTerm>[OrderingTerm(expression: tracks.title.lower())],
      );

  /// Tracks the junk filter auto-hid (title order) — Hidden-songs screen.
  Stream<List<TrackWithMeta>> watchHiddenByFilter() => _watchTracksWhere(
        tracks.visibility.equalsValue(TrackVisibility.hiddenByFilter),
        <OrderingTerm>[OrderingTerm(expression: tracks.title.lower())],
      );

  /// Liked, visible tracks — newest like first. The virtual "Liked Songs".
  Stream<List<TrackWithMeta>> watchLikedTracks() => _watchTracksWhere(
        tracks.liked.equals(true) & _visible(tracks),
        <OrderingTerm>[
          OrderingTerm(expression: tracks.likedAt, mode: OrderingMode.desc),
        ],
      );

  /// Whether [id] is currently liked — drives the heart toggle's filled state
  /// (Now Playing + the track sheet), live.
  Stream<bool> watchLiked(String id) {
    return (select(tracks)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((TrackRow? row) => row?.liked ?? false);
  }

  /// Reactive count of liked visible tracks — the Liked Songs card badge.
  Stream<int> watchLikedCount() {
    final Expression<int> count = tracks.id.count();
    return (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[count])
          ..where(tracks.liked.equals(true) & _visible(tracks)))
        .watchSingle()
        .map((TypedResult r) => r.read(count) ?? 0);
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

  Future<int> deleteTracks(List<String> ids) {
    if (ids.isEmpty) return Future<int>.value(0);
    return (delete(tracks)..where((t) => t.id.isIn(ids))).go();
  }

  // --- Purge support (see LibraryMaintenance) -----------------------------

  /// The raw rows behind [ids], **unfiltered** by visibility — a purge must see
  /// hidden rows too (you can delete a hidden song). Order is not guaranteed.
  Future<List<TrackRow>> trackRowsByIds(List<String> ids) async {
    if (ids.isEmpty) return <TrackRow>[];
    return (select(tracks)..where((t) => t.id.isIn(ids))).get();
  }

  /// Of [albumIds], those that no track references any more — the albums a purge
  /// should delete so an emptied album never lingers in the grid.
  Future<List<AlbumRow>> emptyAlbums(Set<String> albumIds) async {
    if (albumIds.isEmpty) return <AlbumRow>[];
    final List<AlbumRow> candidates =
        await (select(albums)..where((a) => a.id.isIn(albumIds.toList()))).get();
    if (candidates.isEmpty) return <AlbumRow>[];
    final List<TypedResult> live = await (selectOnly(tracks, distinct: true)
          ..addColumns(<Expression<Object>>[tracks.albumId])
          ..where(tracks.albumId.isIn(candidates.map((AlbumRow a) => a.id).toList())))
        .get();
    final Set<String> stillUsed = <String>{
      for (final TypedResult r in live) r.read(tracks.albumId)!,
    };
    return candidates
        .where((AlbumRow a) => !stillUsed.contains(a.id))
        .toList();
  }

  /// Of [artistIds], those with neither tracks nor albums left.
  Future<List<String>> emptyArtists(Set<String> artistIds) async {
    if (artistIds.isEmpty) return <String>[];
    final List<String> ids = artistIds.toList();
    final List<TypedResult> liveTracks = await (selectOnly(tracks, distinct: true)
          ..addColumns(<Expression<Object>>[tracks.artistId])
          ..where(tracks.artistId.isIn(ids)))
        .get();
    final List<TypedResult> liveAlbums = await (selectOnly(albums, distinct: true)
          ..addColumns(<Expression<Object>>[albums.artistId])
          ..where(albums.artistId.isIn(ids)))
        .get();
    final Set<String> stillUsed = <String>{
      for (final TypedResult r in liveTracks) r.read(tracks.artistId)!,
      for (final TypedResult r in liveAlbums) r.read(albums.artistId)!,
    };
    return ids.where((String id) => !stillUsed.contains(id)).toList();
  }

  /// Of [keys], the artwork keys no surviving track or album still points at —
  /// the art files (and cached palettes) a purge may evict.
  Future<List<String>> orphanedArtworkKeys(Set<String> keys) async {
    if (keys.isEmpty) return <String>[];
    final List<String> ids = keys.toList();
    final List<TypedResult> byTrack = await (selectOnly(tracks, distinct: true)
          ..addColumns(<Expression<Object>>[tracks.artworkKey])
          ..where(tracks.artworkKey.isIn(ids)))
        .get();
    final List<TypedResult> byAlbum = await (selectOnly(albums, distinct: true)
          ..addColumns(<Expression<Object>>[albums.artworkKey])
          ..where(albums.artworkKey.isIn(ids)))
        .get();
    final Set<String> stillUsed = <String>{
      for (final TypedResult r in byTrack)
        if (r.read(tracks.artworkKey) != null) r.read(tracks.artworkKey)!,
      for (final TypedResult r in byAlbum)
        if (r.read(albums.artworkKey) != null) r.read(albums.artworkKey)!,
    };
    return ids.where((String key) => !stillUsed.contains(key)).toList();
  }

  Future<int> deleteAlbums(List<String> ids) {
    if (ids.isEmpty) return Future<int>.value(0);
    return (delete(albums)..where((a) => a.id.isIn(ids))).go();
  }

  Future<int> deleteArtists(List<String> ids) {
    if (ids.isEmpty) return Future<int>.value(0);
    return (delete(artists)..where((a) => a.id.isIn(ids))).go();
  }

  /// Flags a track playable/unplayable (see [Tracks.playable]). Called when the
  /// player fails to load a file so playback can route around it.
  Future<void> setTrackPlayable(String id, bool playable) async {
    await (update(tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(playable: Value(playable)));
  }

  /// Sets a track's [Tracks.visibility]. When [userOverride] is passed it's
  /// written too — unhiding sets it true so a future scan never re-filters the
  /// track (see [Tracks.userOverride]).
  ///
  /// The album's `trackCount` is recomputed in the same transaction: counts are
  /// visible-only, so hiding a song must decrement its album (and hiding the last
  /// one takes the album to 0, at which point browsing drops it entirely).
  Future<void> setTrackVisibility(
    String id,
    TrackVisibility visibility, {
    bool? userOverride,
  }) async {
    await transaction(() async {
      final TrackRow? row =
          await (select(tracks)..where((t) => t.id.equals(id)))
              .getSingleOrNull();
      if (row == null) return;
      await (update(tracks)..where((t) => t.id.equals(id)))
          .write(TracksCompanion(
        visibility: Value(visibility),
        userOverride:
            userOverride == null ? const Value.absent() : Value(userOverride),
      ));
      await recomputeAlbumTrackCounts(<String>{row.albumId});
    });
  }

  /// Unhides every track in a hidden bucket ([TrackVisibility.hiddenByUser] or
  /// [TrackVisibility.hiddenByFilter]) → visible + userOverride. "Unhide all".
  Future<void> unhideAll(TrackVisibility from) async {
    await transaction(() async {
      final List<TrackRow> rows =
          await (select(tracks)..where((t) => t.visibility.equalsValue(from)))
              .get();
      if (rows.isEmpty) return;
      await (update(tracks)..where((t) => t.visibility.equalsValue(from))).write(
        const TracksCompanion(
          visibility: Value(TrackVisibility.visible),
          userOverride: Value(true),
        ),
      );
      await recomputeAlbumTrackCounts(
        rows.map((TrackRow r) => r.albumId).toSet(),
      );
    });
  }

  /// Likes/unlikes a track, stamping [Tracks.likedAt] with [at] (now) on like
  /// and clearing it on unlike.
  Future<void> setLiked(String id, bool liked, {DateTime? at}) async {
    await (update(tracks)..where((t) => t.id.equals(id))).write(TracksCompanion(
      liked: Value(liked),
      likedAt: Value(liked ? (at ?? DateTime.now()) : null),
    ));
  }

  /// The persisted flags of the given track ids, keyed by id — unfiltered (must
  /// see hidden rows). The scanner reads these before an upsert so a rescan
  /// preserves the user's like + hide/unhide choices (see resolveVisibility).
  Future<
      Map<
        String,
        ({
          TrackVisibility visibility,
          bool userOverride,
          bool liked,
          DateTime? likedAt,
        })
      >> trackFlags(List<String> ids) async {
    if (ids.isEmpty) {
      return const <String,
          ({
            TrackVisibility visibility,
            bool userOverride,
            bool liked,
            DateTime? likedAt,
          })>{};
    }
    final List<TrackRow> rows =
        await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    return <String,
        ({
          TrackVisibility visibility,
          bool userOverride,
          bool liked,
          DateTime? likedAt,
        })>{
      for (final TrackRow r in rows)
        r.id: (
          visibility: r.visibility,
          userOverride: r.userOverride,
          liked: r.liked,
          likedAt: r.likedAt,
        ),
    };
  }

  // --- Synthetic seed data (debug) ----------------------------------------

  /// Deletes every synthetic row (ids under the `local:synthetic:` marker
  /// prefix) across tracks, albums and artists — the "clear synthetic" action.
  /// Returns the number of tracks removed.
  Future<int> deleteSyntheticData() async {
    const String pattern = 'local:synthetic:%';
    int removed = 0;
    await transaction(() async {
      removed =
          await (delete(tracks)..where((t) => t.id.like(pattern))).go();
      await (delete(albums)..where((t) => t.id.like(pattern))).go();
      await (delete(artists)..where((t) => t.id.like(pattern))).go();
    });
    return removed;
  }

  // --- Tag-repair sweep ---------------------------------------------------

  /// One-shot reads of the display-name-bearing rows, for the mojibake repair
  /// pass. Deliberate `get()`s (a one-time maintenance sweep, not reactive UI).
  Future<List<TrackRow>> allTrackRows() => select(tracks).get();
  Future<List<AlbumRow>> allAlbumRows() => select(albums).get();
  Future<List<ArtistRow>> allArtistRows() => select(artists).get();

  /// Applies repaired display strings in one batch: track titles, album names,
  /// artist names (keyed by id). Empty maps are no-ops.
  Future<void> applyTagRepairs({
    Map<String, String> trackTitles = const <String, String>{},
    Map<String, String> albumNames = const <String, String>{},
    Map<String, String> artistNames = const <String, String>{},
  }) async {
    if (trackTitles.isEmpty && albumNames.isEmpty && artistNames.isEmpty) {
      return;
    }
    await batch((Batch b) {
      trackTitles.forEach((String id, String title) {
        b.update(
          tracks,
          TracksCompanion(title: Value(title)),
          where: ($TracksTable t) => t.id.equals(id),
        );
      });
      albumNames.forEach((String id, String name) {
        b.update(
          albums,
          AlbumsCompanion(name: Value(name)),
          where: ($AlbumsTable t) => t.id.equals(id),
        );
      });
      artistNames.forEach((String id, String name) {
        b.update(
          artists,
          ArtistsCompanion(name: Value(name)),
          where: ($ArtistsTable t) => t.id.equals(id),
        );
      });
    });
  }

  // --- Scanner support ----------------------------------------------------

  Future<int> trackCount() async {
    final Expression<int> count = tracks.id.count();
    final TypedResult row =
        await (selectOnly(tracks)..addColumns(<Expression<Object>>[count]))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Lightweight (id, dateModified, source) snapshot of every track — the input
  /// the incremental scan diff compares MediaStore against.
  Future<List<({String id, DateTime dateModified, TrackSource source})>>
  trackSnapshots() async {
    final List<TypedResult> rows = await (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[
            tracks.id,
            tracks.dateModified,
            tracks.source,
          ]))
        .get();
    return rows
        .map(
          (TypedResult r) => (
            id: r.read(tracks.id)!,
            dateModified: r.read(tracks.dateModified)!,
            source: r.readWithConverter(tracks.source)!,
          ),
        )
        .toList();
  }

  /// Recomputes `trackCount` for the given albums from the current tracks.
  ///
  /// Counts **visible** tracks only, so the number on an album card matches the
  /// list you get when you open it (and an album whose tracks are all hidden
  /// reads 0 — it's a ghost, and browsing filters it out entirely).
  Future<void> recomputeAlbumTrackCounts(Set<String> albumIds) async {
    if (albumIds.isEmpty) return;
    final Expression<int> count = tracks.id.count();
    final List<TypedResult> rows = await (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[tracks.albumId, count])
          ..where(tracks.albumId.isIn(albumIds.toList()) & _visible(tracks))
          ..groupBy(<Expression<Object>>[tracks.albumId]))
        .get();
    final Map<String, int> counts = <String, int>{
      for (final TypedResult r in rows) r.read(tracks.albumId)!: r.read(count) ?? 0,
    };
    await batch((Batch b) {
      for (final String albumId in albumIds) {
        b.update(
          albums,
          AlbumsCompanion(trackCount: Value(counts[albumId] ?? 0)),
          where: ($AlbumsTable a) => a.id.equals(albumId),
        );
      }
    });
  }

  /// Recomputes `trackCount` for **every** album (visible tracks only).
  ///
  /// The scanner runs this at the end of a scan so counts self-heal: an
  /// incremental scan only touches the albums it wrote, and a library written
  /// before counts became visibility-aware would otherwise keep stale numbers on
  /// albums nothing happened to touch. One grouped read + one batch write.
  Future<void> recomputeAllAlbumTrackCounts() async {
    final Expression<int> count = tracks.id.count();
    final List<TypedResult> rows = await (selectOnly(tracks)
          ..addColumns(<Expression<Object>>[tracks.albumId, count])
          ..where(_visible(tracks))
          ..groupBy(<Expression<Object>>[tracks.albumId]))
        .get();
    final Map<String, int> counts = <String, int>{
      for (final TypedResult r in rows)
        r.read(tracks.albumId)!: r.read(count) ?? 0,
    };
    final List<AlbumRow> all = await select(albums).get();
    await batch((Batch b) {
      for (final AlbumRow album in all) {
        final int fresh = counts[album.id] ?? 0;
        if (fresh == album.trackCount) continue;
        b.update(
          albums,
          AlbumsCompanion(trackCount: Value(fresh)),
          where: ($AlbumsTable a) => a.id.equals(album.id),
        );
      }
    });
  }

  /// Stamps an album and all its tracks with a resolved artwork key (called in
  /// the scanner's artwork phase once the file is on disk).
  Future<void> setAlbumArtwork(String albumId, String artworkKey) async {
    await (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(artworkKey: Value(artworkKey)),
    );
    await (update(tracks)..where((t) => t.albumId.equals(albumId))).write(
      TracksCompanion(artworkKey: Value(artworkKey)),
    );
  }
}
