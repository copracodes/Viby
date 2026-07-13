import '../../db/tables.dart';
import '../../db/viby_database.dart';
import 'song_mapper.dart';

/// The deletable subset of a selection, ready for the platform delete request.
///
/// The three lists are index-aligned: `mediaIds[i]` / `paths[i]` belong to
/// `trackIds[i]`.
class DeleteTargets {
  const DeleteTargets({
    required this.trackIds,
    required this.mediaIds,
    required this.paths,
    required this.skipped,
  });

  const DeleteTargets.empty()
      : trackIds = const <String>[],
        mediaIds = const <int>[],
        paths = const <String?>[],
        skipped = 0;

  final List<String> trackIds;
  final List<int> mediaIds;
  final List<String?> paths;

  /// Rows rejected by the guard (not local, or not MediaStore-backed).
  final int skipped;

  bool get isEmpty => trackIds.isEmpty;
  int get length => trackIds.length;
}

/// The **source guard**: only `local` tracks that map back to a real MediaStore
/// row can be deleted from the device.
///
/// A `subsonic` row is a pointer at someone else's server — deleting it here
/// would mean nothing (and must never reach the platform call). Synthetic seeded
/// rows (`local:synthetic:…`) have no MediaStore id either, so they're rejected
/// by the same rule: [mediaStoreIdFromTrackId] returns null for both.
DeleteTargets resolveDeleteTargets(List<TrackRow> rows) {
  final List<String> trackIds = <String>[];
  final List<int> mediaIds = <int>[];
  final List<String?> paths = <String?>[];
  int skipped = 0;

  for (final TrackRow row in rows) {
    final int? mediaId = row.source == TrackSource.local
        ? mediaStoreIdFromTrackId(row.id)
        : null;
    if (mediaId == null) {
      skipped++;
      continue;
    }
    trackIds.add(row.id);
    mediaIds.add(mediaId);
    paths.add(row.filePath);
  }

  return DeleteTargets(
    trackIds: trackIds,
    mediaIds: mediaIds,
    paths: paths,
    skipped: skipped,
  );
}
