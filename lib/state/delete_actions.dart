import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/viby_database.dart';
import '../data/sources/local/delete_targets.dart';
import '../data/sources/local/media_delete_channel.dart';
import 'library_providers.dart';
import 'queue_provider.dart';

/// Permanently deletes [rows]' files from the device, then cleans up the library.
///
/// The order is the whole safety story: **nothing in the DB changes until the
/// platform confirms the files are gone**. A [DeleteOutcome.denied] (the user
/// declined the system dialog) is a silent no-op; a [DeleteOutcome.failed]
/// (read-only card, locked file) leaves the library exactly as it was, so we
/// never show a song as deleted while the file still sits on disk.
///
/// On success the purge runs through the shared [LibraryMaintenance] choke point
/// — the same one the incremental scanner uses when a file disappears — and the
/// deleted tracks leave the queue (a playing copy advances; the last one stops).
///
/// Rows that fail the source guard (Subsonic, synthetic) are dropped by
/// [resolveDeleteTargets] and never reach the platform call.
Future<DeleteOutcome> deleteTracksFromDevice(
  WidgetRef ref,
  List<TrackRow> rows,
) async {
  final MediaDeleter deleter = ref.read(mediaDeleterProvider);
  if (!deleter.capable) return DeleteOutcome.failed;

  final DeleteTargets targets = resolveDeleteTargets(rows);
  if (targets.isEmpty) return DeleteOutcome.failed;

  final DeleteOutcome outcome = await deleter.deleteTracks(
    mediaIds: targets.mediaIds,
    paths: targets.paths,
  );
  if (outcome != DeleteOutcome.granted) return outcome;

  await ref.read(libraryMaintenanceProvider).purgeTracks(targets.trackIds);
  for (final String id in targets.trackIds) {
    await ref.read(queueControllerProvider.notifier).removeTrackById(id);
  }
  return DeleteOutcome.granted;
}
