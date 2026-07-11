import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'lyrics_dao.g.dart';

/// The lyrics cache: one row per track holding the raw resolved document plus
/// denormalized flags. Reads are one-shot `get()` (lyrics attach to the *current
/// track*, not a reactive list — this is an allowed non-list read), while a
/// `watch()` on the single current track powers the Now Playing binding.
@DriftAccessor(tables: <Type>[LyricsLines])
class LyricsDao extends DatabaseAccessor<VibyDatabase> with _$LyricsDaoMixin {
  LyricsDao(super.db);

  /// The cached lyrics row for [trackId], or null if never resolved.
  Future<LyricsRow?> getForTrack(String trackId) {
    return (select(lyricsLines)..where((t) => t.trackId.equals(trackId)))
        .getSingleOrNull();
  }

  /// Reactive lyrics for [trackId] — emits null until resolved, then the row.
  /// The Now Playing view watches exactly one track's lyrics this way.
  Stream<LyricsRow?> watchForTrack(String trackId) {
    return (select(lyricsLines)..where((t) => t.trackId.equals(trackId)))
        .watchSingleOrNull();
  }

  /// Upserts the resolved lyrics for a track (idempotent by `trackId`).
  Future<void> upsert({
    required String trackId,
    required LyricsSource source,
    required bool synced,
    required String rawText,
    required bool parsedOk,
    DateTime? resolvedAt,
  }) {
    return into(lyricsLines).insertOnConflictUpdate(
      LyricsRow(
        trackId: trackId,
        source: source,
        synced: synced,
        rawText: rawText,
        parsedOk: parsedOk,
        resolvedAt: resolvedAt ?? DateTime.now(),
      ),
    );
  }

  /// Drops the cached lyrics for [trackId] (used by "Refresh lyrics" and by the
  /// scanner when a track's file changed, so lyrics re-resolve on next play).
  Future<void> deleteForTrack(String trackId) {
    return (delete(lyricsLines)..where((t) => t.trackId.equals(trackId))).go();
  }

  /// Drops cached lyrics for many tracks at once (incremental-scan invalidation).
  Future<void> deleteForTracks(Iterable<String> trackIds) async {
    final List<String> ids = trackIds.toList(growable: false);
    if (ids.isEmpty) return;
    await (delete(lyricsLines)..where((t) => t.trackId.isIn(ids))).go();
  }

  /// Clears the whole lyrics cache — used when the lyrics folder grant changes,
  /// so every track re-resolves and a now-reachable sidecar can outrank an
  /// embedded fallback that was cached earlier.
  Future<void> clearAll() => delete(lyricsLines).go();
}
