import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'search_dao.g.dart';

/// Recent search terms. A term is recorded when the user acts on a result;
/// only the most recent [kMaxRecentSearches] are kept.
@DriftAccessor(tables: <Type>[Searches])
class SearchDao extends DatabaseAccessor<VibyDatabase> with _$SearchDaoMixin {
  SearchDao(super.db);

  /// How many recent terms are retained.
  static const int kMaxRecentSearches = 10;

  /// The most recent terms (newest first), capped at [kMaxRecentSearches].
  Stream<List<String>> watchRecentSearches({
    int limit = kMaxRecentSearches,
  }) {
    return (select(searches)
          ..orderBy(<OrderClauseGenerator<$SearchesTable>>[
            (t) => OrderingTerm(
                  expression: t.lastUsed,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .watch()
        .map((List<SearchRow> rows) =>
            rows.map((SearchRow r) => r.query).toList());
  }

  /// Records a successful search: upserts the term with a fresh timestamp and
  /// prunes anything past the newest [kMaxRecentSearches]. Blank queries are
  /// ignored. [at] overrides the timestamp (tests only — drift stores
  /// `DateTime` at one-second resolution, so ordering needs distinct seconds).
  Future<void> recordSearch(String query, {DateTime? at}) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    await transaction(() async {
      await into(searches).insertOnConflictUpdate(
        SearchRow(query: q, lastUsed: at ?? DateTime.now()),
      );
      await _prune();
    });
  }

  Future<void> clearSearches() async {
    await delete(searches).go();
  }

  /// Deletes all but the newest [kMaxRecentSearches] terms. Call in a
  /// transaction alongside the insert.
  Future<void> _prune() async {
    final List<SearchRow> keep = await (select(searches)
          ..orderBy(<OrderClauseGenerator<$SearchesTable>>[
            (t) => OrderingTerm(
                  expression: t.lastUsed,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(kMaxRecentSearches))
        .get();
    if (keep.length < kMaxRecentSearches) return;
    final List<String> keepQueries =
        keep.map((SearchRow r) => r.query).toList();
    await (delete(searches)..where((t) => t.query.isNotIn(keepQueries))).go();
  }
}
