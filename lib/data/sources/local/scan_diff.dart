import '../../db/tables.dart';

/// A MediaStore track as seen by a scan: its deterministic id and last-modified
/// time (epoch seconds, as MediaStore reports it).
class MediaSnapshotEntry {
  const MediaSnapshotEntry({required this.id, required this.dateModified});

  final String id;
  final int dateModified;
}

/// A stored track reduced to what the diff needs: id, last-modified (epoch
/// seconds) and source (so subsonic rows are never touched by a local scan).
class DbSnapshotEntry {
  const DbSnapshotEntry({
    required this.id,
    required this.dateModified,
    required this.source,
  });

  final String id;
  final int dateModified;
  final TrackSource source;
}

/// The outcome of comparing MediaStore against the DB.
class ScanDiff {
  const ScanDiff({
    required this.added,
    required this.changed,
    required this.deleted,
  });

  /// Ids present in MediaStore but not the DB.
  final Set<String> added;

  /// Ids present in both whose `dateModified` differs.
  final Set<String> changed;

  /// Ids present in the DB (source == local) but gone from MediaStore.
  final Set<String> deleted;

  Set<String> get upserts => <String>{...added, ...changed};

  bool get isEmpty => added.isEmpty && changed.isEmpty && deleted.isEmpty;
}

/// Pure incremental-scan diff. Classifies MediaStore entries as added/changed
/// and finds local DB rows to delete. **Never** marks a non-local (e.g.
/// subsonic) row for deletion, even if absent from MediaStore.
ScanDiff computeScanDiff(
  List<MediaSnapshotEntry> mediaStore,
  List<DbSnapshotEntry> db,
) {
  final Map<String, DbSnapshotEntry> dbById = <String, DbSnapshotEntry>{
    for (final DbSnapshotEntry e in db) e.id: e,
  };
  final Set<String> mediaIds = <String>{};
  final Set<String> added = <String>{};
  final Set<String> changed = <String>{};

  for (final MediaSnapshotEntry m in mediaStore) {
    mediaIds.add(m.id);
    final DbSnapshotEntry? existing = dbById[m.id];
    if (existing == null) {
      added.add(m.id);
    } else if (existing.dateModified != m.dateModified) {
      changed.add(m.id);
    }
  }

  final Set<String> deleted = <String>{};
  for (final DbSnapshotEntry e in db) {
    if (e.source == TrackSource.local && !mediaIds.contains(e.id)) {
      deleted.add(e.id);
    }
  }

  return ScanDiff(added: added, changed: changed, deleted: deleted);
}
