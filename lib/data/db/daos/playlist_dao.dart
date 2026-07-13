import 'dart:math';

import 'package:drift/drift.dart';

import '../tables.dart';
import '../util/stream_combine.dart';
import '../viby_database.dart';
import 'library_dao.dart';

part 'playlist_dao.g.dart';

/// A playlist with its tracks, ordered by playlist position.
class PlaylistWithTracks {
  const PlaylistWithTracks({required this.playlist, required this.tracks});

  final PlaylistRow playlist;
  final List<TrackRow> tracks;
}

/// A playlist with its tracks (+ resolved album/artist names) in position
/// order — the shape the playlist-detail screen renders.
class PlaylistWithMeta {
  const PlaylistWithMeta({required this.playlist, required this.tracks});

  final PlaylistRow playlist;
  final List<TrackWithMeta> tracks;
}

/// A playlist plus the derived data the grid card needs: how many (resolvable)
/// tracks it holds and up to four distinct album-art keys for the collage.
class PlaylistSummary {
  const PlaylistSummary({
    required this.playlist,
    required this.trackCount,
    required this.artworkKeys,
  });

  final PlaylistRow playlist;
  final int trackCount;
  final List<String> artworkKeys;
}

/// Picks up to [max] distinct, non-empty artwork keys from [keysInOrder]
/// (position order), preserving first-seen order — the 2×2 collage source.
/// Pure so the collage rule is unit-testable.
List<String> pickCollageKeys(List<String?> keysInOrder, {int max = 4}) {
  final List<String> result = <String>[];
  final Set<String> seen = <String>{};
  for (final String? key in keysInOrder) {
    if (key == null || key.isEmpty) continue;
    if (seen.add(key)) result.add(key);
    if (result.length >= max) break;
  }
  return result;
}

/// Playlists and their ordered entries. Position is kept dense (0..n-1); all
/// multi-row mutations run in a transaction.
@DriftAccessor(
  tables: <Type>[Playlists, PlaylistEntries, Tracks, Albums, Artists],
)
class PlaylistDao extends DatabaseAccessor<VibyDatabase>
    with _$PlaylistDaoMixin {
  PlaylistDao(super.db);

  final Random _random = Random();

  Stream<List<PlaylistRow>> watchPlaylists() {
    return (select(playlists)
          ..orderBy(<OrderClauseGenerator<$PlaylistsTable>>[
            (t) => OrderingTerm(
              expression: t.dateModified,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Playlist + its tracks in position order. Null while the id is unknown.
  Stream<PlaylistWithTracks?> watchPlaylistWithTracks(String id) {
    final Stream<PlaylistRow?> playlistStream =
        (select(playlists)..where((t) => t.id.equals(id)))
            .watchSingleOrNull();
    final JoinedSelectStatement<HasResultSet, dynamic> entriesQuery =
        select(playlistEntries).join(<Join<HasResultSet, dynamic>>[
          innerJoin(tracks, tracks.id.equalsExp(playlistEntries.trackId)),
        ])
          ..where(playlistEntries.playlistId.equals(id) &
              tracks.visibility.equalsValue(TrackVisibility.visible))
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: playlistEntries.position),
          ]);
    final Stream<List<TrackRow>> tracksStream = entriesQuery.watch().map(
      (List<TypedResult> rows) =>
          rows.map((TypedResult r) => r.readTable(tracks)).toList(),
    );
    return combineLatest2<PlaylistRow?, List<TrackRow>, PlaylistWithTracks?>(
      playlistStream,
      tracksStream,
      (PlaylistRow? playlist, List<TrackRow> rows) => playlist == null
          ? null
          : PlaylistWithTracks(playlist: playlist, tracks: rows),
    );
  }

  /// Every playlist (newest-modified first) with its track count and collage
  /// keys — the Playlists grid. One reactive join, grouped in Dart. Entries
  /// whose track has been pruned are ignored (matches the inner-joined detail).
  Stream<List<PlaylistSummary>> watchPlaylistSummaries() {
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        select(playlists).join(<Join<HasResultSet, dynamic>>[
          leftOuterJoin(
            playlistEntries,
            playlistEntries.playlistId.equalsExp(playlists.id),
          ),
          // Visibility on the JOIN (not a WHERE) so a playlist with no visible
          // tracks still appears with a 0 count instead of dropping out.
          leftOuterJoin(
            tracks,
            tracks.id.equalsExp(playlistEntries.trackId) &
                tracks.visibility.equalsValue(TrackVisibility.visible),
          ),
        ])
          ..orderBy(<OrderingTerm>[
            OrderingTerm(
              expression: playlists.dateModified,
              mode: OrderingMode.desc,
            ),
            OrderingTerm(expression: playlistEntries.position),
          ]);
    return query.watch().map((List<TypedResult> rows) {
      // Insertion order follows dateModified desc (first row per playlist).
      final Map<String, _SummaryAccumulator> byId =
          <String, _SummaryAccumulator>{};
      for (final TypedResult row in rows) {
        final PlaylistRow playlist = row.readTable(playlists);
        final _SummaryAccumulator acc = byId.putIfAbsent(
          playlist.id,
          () => _SummaryAccumulator(playlist),
        );
        final TrackRow? track = row.readTableOrNull(tracks);
        if (track != null) {
          acc.count++;
          acc.artworkKeys.add(track.artworkKey);
        }
      }
      return byId.values
          .map(
            (_SummaryAccumulator a) => PlaylistSummary(
              playlist: a.playlist,
              trackCount: a.count,
              artworkKeys: pickCollageKeys(a.artworkKeys),
            ),
          )
          .toList();
    });
  }

  /// Playlist + its tracks (with album/artist names) in position order. Null
  /// while the id is unknown; re-emits as either side changes.
  Stream<PlaylistWithMeta?> watchPlaylistWithMeta(String id) {
    final Stream<PlaylistRow?> playlistStream =
        (select(playlists)..where((t) => t.id.equals(id)))
            .watchSingleOrNull();
    final JoinedSelectStatement<HasResultSet, dynamic> entriesQuery =
        select(playlistEntries).join(<Join<HasResultSet, dynamic>>[
          innerJoin(tracks, tracks.id.equalsExp(playlistEntries.trackId)),
          leftOuterJoin(albums, albums.id.equalsExp(tracks.albumId)),
          leftOuterJoin(artists, artists.id.equalsExp(tracks.artistId)),
        ])
          ..where(playlistEntries.playlistId.equals(id) &
              tracks.visibility.equalsValue(TrackVisibility.visible))
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: playlistEntries.position),
          ]);
    final Stream<List<TrackWithMeta>> tracksStream = entriesQuery.watch().map(
      (List<TypedResult> rows) => rows
          .map(
            (TypedResult r) => TrackWithMeta(
              track: r.readTable(tracks),
              albumName: r.readTableOrNull(albums)?.name,
              artistName: r.readTableOrNull(artists)?.name,
            ),
          )
          .toList(),
    );
    return combineLatest2<PlaylistRow?, List<TrackWithMeta>, PlaylistWithMeta?>(
      playlistStream,
      tracksStream,
      (PlaylistRow? playlist, List<TrackWithMeta> rows) => playlist == null
          ? null
          : PlaylistWithMeta(playlist: playlist, tracks: rows),
    );
  }

  /// The set of playlist ids that currently contain [trackId] — powers the
  /// checkmarks in the "Add to playlist" sheet.
  Stream<Set<String>> watchPlaylistIdsContaining(String trackId) {
    return (selectOnly(playlistEntries, distinct: true)
          ..addColumns(<Expression<Object>>[playlistEntries.playlistId])
          ..where(playlistEntries.trackId.equals(trackId)))
        .watch()
        .map(
          (List<TypedResult> rows) => rows
              .map((TypedResult r) => r.read(playlistEntries.playlistId)!)
              .toSet(),
        );
  }

  /// Toggles [trackId]'s membership in [playlistId]: appends it if absent
  /// (returns true), or removes every occurrence and re-compacts if present
  /// (returns false). Existing order is otherwise untouched.
  Future<bool> toggleTrack(String playlistId, String trackId) async {
    final List<PlaylistEntryRow> existing = await (select(playlistEntries)
          ..where(
            (t) => t.playlistId.equals(playlistId) & t.trackId.equals(trackId),
          ))
        .get();
    if (existing.isEmpty) {
      await addTracks(playlistId, <String>[trackId]);
      return true;
    }
    await transaction(() async {
      await (delete(playlistEntries)
            ..where(
              (t) =>
                  t.playlistId.equals(playlistId) & t.trackId.equals(trackId),
            ))
          .go();
      await _recompact(playlistId);
      await _touch(playlistId);
    });
    return false;
  }

  /// Creates a playlist and returns its freshly-minted id.
  Future<String> createPlaylist(String name) async {
    final String id =
        'playlist:${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';
    final DateTime now = DateTime.now();
    await into(playlists).insert(
      PlaylistsCompanion.insert(
        id: id,
        name: name,
        dateCreated: now,
        dateModified: now,
      ),
    );
    return id;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await (update(playlists)..where((t) => t.id.equals(id))).write(
      PlaylistsCompanion(
        name: Value(name),
        dateModified: Value(DateTime.now()),
      ),
    );
  }

  /// Deletes a playlist; its entries cascade away.
  Future<void> deletePlaylist(String id) async {
    await (delete(playlists)..where((t) => t.id.equals(id))).go();
  }

  /// Appends [trackIds] to the end of the playlist, keeping positions dense.
  Future<void> addTracks(String playlistId, List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await transaction(() async {
      final List<PlaylistEntryRow> existing = await (select(playlistEntries)
            ..where((t) => t.playlistId.equals(playlistId)))
          .get();
      int nextPosition = existing.length; // positions are dense 0..n-1
      await batch((Batch b) {
        for (final String trackId in trackIds) {
          b.insert(
            playlistEntries,
            PlaylistEntriesCompanion.insert(
              playlistId: playlistId,
              trackId: trackId,
              position: nextPosition++,
            ),
          );
        }
      });
      await _touch(playlistId);
    });
  }

  /// Removes the entry at [position] and re-compacts remaining positions.
  Future<void> removeEntry({
    required String playlistId,
    required int position,
  }) async {
    await transaction(() async {
      await (delete(playlistEntries)
            ..where(
              (t) =>
                  t.playlistId.equals(playlistId) &
                  t.position.equals(position),
            ))
          .go();
      await _recompact(playlistId);
      await _touch(playlistId);
    });
  }

  /// Drops every entry referencing any of [trackIds] from **every** playlist and
  /// re-compacts the affected playlists' positions. Called when tracks are purged
  /// (deleted from device / gone from MediaStore): `trackId` is a plain key, not
  /// an FK, so nothing cascades for us. Idempotent — a second call finds nothing
  /// to remove and touches no playlist.
  Future<void> removeTracksFromAllPlaylists(List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await transaction(() async {
      final List<PlaylistEntryRow> doomed = await (select(playlistEntries)
            ..where((t) => t.trackId.isIn(trackIds)))
          .get();
      if (doomed.isEmpty) return;
      final Set<String> affected = <String>{
        for (final PlaylistEntryRow e in doomed) e.playlistId,
      };
      await (delete(playlistEntries)..where((t) => t.trackId.isIn(trackIds))).go();
      for (final String playlistId in affected) {
        await _recompact(playlistId);
        await _touch(playlistId);
      }
    });
  }

  /// Moves the entry at index [from] to index [to], rewriting positions so they
  /// remain dense and correct.
  Future<void> reorderEntry({
    required String playlistId,
    required int from,
    required int to,
  }) async {
    if (from == to) return;
    await transaction(() async {
      final List<PlaylistEntryRow> entries = await (select(playlistEntries)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy(<OrderClauseGenerator<$PlaylistEntriesTable>>[
              (t) => OrderingTerm(expression: t.position),
            ]))
          .get();
      if (from < 0 ||
          from >= entries.length ||
          to < 0 ||
          to >= entries.length) {
        return;
      }
      final PlaylistEntryRow moved = entries.removeAt(from);
      entries.insert(to, moved);
      await batch((Batch b) {
        for (int i = 0; i < entries.length; i++) {
          b.update(
            playlistEntries,
            PlaylistEntriesCompanion(position: Value(i)),
            where: (t) => t.id.equals(entries[i].id),
          );
        }
      });
      await _touch(playlistId);
    });
  }

  /// Rewrites positions of a playlist's entries to a dense 0..n-1 sequence in
  /// their current order. Call inside a transaction.
  Future<void> _recompact(String playlistId) async {
    final List<PlaylistEntryRow> remaining = await (select(playlistEntries)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy(<OrderClauseGenerator<$PlaylistEntriesTable>>[
            (t) => OrderingTerm(expression: t.position),
          ]))
        .get();
    await batch((Batch b) {
      for (int i = 0; i < remaining.length; i++) {
        b.update(
          playlistEntries,
          PlaylistEntriesCompanion(position: Value(i)),
          where: (t) => t.id.equals(remaining[i].id),
        );
      }
    });
  }

  Future<void> _touch(String playlistId) async {
    await (update(playlists)..where((t) => t.id.equals(playlistId))).write(
      PlaylistsCompanion(dateModified: Value(DateTime.now())),
    );
  }
}

/// Mutable per-playlist accumulator used while folding the summaries join.
class _SummaryAccumulator {
  _SummaryAccumulator(this.playlist);

  final PlaylistRow playlist;
  int count = 0;
  final List<String?> artworkKeys = <String?>[];
}
