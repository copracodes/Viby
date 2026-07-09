import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'history_dao.g.dart';

/// The play log: recording plays and deriving recently/most played tracks.
@DriftAccessor(tables: <Type>[PlayHistory, Tracks])
class HistoryDao extends DatabaseAccessor<VibyDatabase>
    with _$HistoryDaoMixin {
  HistoryDao(super.db);

  /// Appends a play event. [playedAt] defaults to now.
  Future<void> recordPlay({
    required String trackId,
    DateTime? playedAt,
    bool completed = false,
  }) async {
    await into(playHistory).insert(
      PlayHistoryCompanion.insert(
        trackId: trackId,
        playedAt: playedAt ?? DateTime.now(),
        completed: Value(completed),
      ),
    );
  }

  /// Distinct tracks ordered by their most recent play (newest first).
  Stream<List<TrackRow>> watchRecentlyPlayed({int limit = 50}) {
    final Expression<DateTime> lastPlayed = playHistory.playedAt.max();
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          innerJoin(playHistory, playHistory.trackId.equalsExp(tracks.id)),
        ])
          ..where(tracks.visibility.equalsValue(TrackVisibility.visible))
          ..groupBy(<Expression<Object>>[tracks.id])
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: lastPlayed, mode: OrderingMode.desc),
          ])
          ..limit(limit);
    return query.watch().map(
      (List<TypedResult> rows) =>
          rows.map((TypedResult r) => r.readTable(tracks)).toList(),
    );
  }

  /// Distinct tracks ordered by play count (most first).
  Stream<List<TrackRow>> watchMostPlayed({int limit = 50}) {
    final Expression<int> playCount = playHistory.id.count();
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        select(tracks).join(<Join<HasResultSet, dynamic>>[
          innerJoin(playHistory, playHistory.trackId.equalsExp(tracks.id)),
        ])
          ..where(tracks.visibility.equalsValue(TrackVisibility.visible))
          ..groupBy(<Expression<Object>>[tracks.id])
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: playCount, mode: OrderingMode.desc),
          ])
          ..limit(limit);
    return query.watch().map(
      (List<TypedResult> rows) =>
          rows.map((TypedResult r) => r.readTable(tracks)).toList(),
    );
  }
}
