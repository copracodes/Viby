import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'cache_dao.g.dart';

/// Bookkeeping for the offline cache: per-track state plus the queries the
/// eviction policy needs.
@DriftAccessor(tables: <Type>[CacheEntries])
class CacheDao extends DatabaseAccessor<VibyDatabase> with _$CacheDaoMixin {
  CacheDao(super.db);

  Future<void> upsertCacheEntry(CacheEntriesCompanion entry) {
    return into(cacheEntries).insertOnConflictUpdate(entry);
  }

  Future<void> deleteCacheEntry(String trackId) async {
    await (delete(cacheEntries)..where((t) => t.trackId.equals(trackId))).go();
  }

  Future<CacheEntryRow?> getCacheEntry(String trackId) {
    return (select(cacheEntries)..where((t) => t.trackId.equals(trackId)))
        .getSingleOrNull();
  }

  Stream<CacheEntryRow?> watchCacheEntry(String trackId) {
    return (select(cacheEntries)..where((t) => t.trackId.equals(trackId)))
        .watchSingleOrNull();
  }

  /// Total bytes held by unpinned entries — the pool eviction can reclaim.
  Future<int> totalUnpinnedBytes() async {
    final Expression<int> total = cacheEntries.bytes.sum();
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        selectOnly(cacheEntries)
          ..addColumns(<Expression<Object>>[total])
          ..where(cacheEntries.pinned.equals(false));
    final TypedResult row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// Unpinned entries ordered by least-recently-accessed first. Pinned entries
  /// are never returned.
  Future<List<CacheEntryRow>> evictionCandidates({int limit = 20}) {
    return (select(cacheEntries)
          ..where((t) => t.pinned.equals(false))
          ..orderBy(<OrderClauseGenerator<$CacheEntriesTable>>[
            (t) => OrderingTerm(expression: t.lastAccessed),
          ])
          ..limit(limit))
        .get();
  }
}
