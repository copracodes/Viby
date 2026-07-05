import 'dart:math';

import 'package:drift/drift.dart';

import '../tables.dart';
import '../util/stream_combine.dart';
import '../viby_database.dart';

part 'playlist_dao.g.dart';

/// A playlist with its tracks, ordered by playlist position.
class PlaylistWithTracks {
  const PlaylistWithTracks({required this.playlist, required this.tracks});

  final PlaylistRow playlist;
  final List<TrackRow> tracks;
}

/// Playlists and their ordered entries. Position is kept dense (0..n-1); all
/// multi-row mutations run in a transaction.
@DriftAccessor(tables: <Type>[Playlists, PlaylistEntries, Tracks])
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
          ..where(playlistEntries.playlistId.equals(id))
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
