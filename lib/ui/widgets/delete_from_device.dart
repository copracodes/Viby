import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/viby_database.dart';
import '../../data/sources/local/delete_targets.dart';
import '../../data/sources/local/media_delete_channel.dart';
import '../../state/delete_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';

/// Runs the "Delete from device" flow for [rows] and reports the outcome.
///
/// Who shows the confirmation depends on the platform, and exactly one of them
/// ever does:
/// * **API 30+** — `MediaStore.createDeleteRequest` makes the *system* ask
///   ("Allow Viby to delete this file?"), so the app adds no dialog of its own.
///   Two dialogs in a row feel broken.
/// * **API ≤ 29** — the system asks nothing, so the app shows its own destructive
///   dialog (naming the track, and pointing at Hide as the non-destructive way out).
///
/// Deletion is permanent, so there is **no undo** offered on success — a fake undo
/// would be a lie. That's what Hide is for.
Future<void> showDeleteFromDevice(
  BuildContext context,
  WidgetRef ref,
  List<TrackRow> rows,
) async {
  final MediaDeleter deleter = ref.read(mediaDeleterProvider);
  if (!deleter.capable) return;

  // Source guard: Subsonic / synthetic rows can't be deleted from the device.
  final DeleteTargets targets = resolveDeleteTargets(rows);
  if (targets.isEmpty) return;

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final List<TrackRow> deletable = rows
      .where((TrackRow r) => targets.trackIds.contains(r.id))
      .toList();

  if (!await deleter.systemConfirms()) {
    if (!context.mounted) return;
    final bool confirmed = await _confirmLegacy(context, deletable);
    if (!confirmed) return;
  }

  final DeleteOutcome outcome = await deleteTracksFromDevice(ref, deletable);
  switch (outcome) {
    case DeleteOutcome.granted:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            deletable.length == 1
                ? 'Deleted "${deletable.single.title}"'
                : 'Deleted ${deletable.length} songs',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    case DeleteOutcome.denied:
      break; // the user said no — say nothing
    case DeleteOutcome.failed:
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete — file may be on a read-only card"),
          duration: Duration(seconds: 3),
        ),
      );
  }
}

/// The app's own confirmation, shown ONLY on API ≤ 29 where the system shows none.
Future<bool> _confirmLegacy(BuildContext context, List<TrackRow> rows) async {
  final ThemeData theme = Theme.of(context);
  final bool single = rows.length == 1;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(single ? 'Delete permanently?' : 'Delete ${rows.length} songs?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            single
                ? '"${rows.single.title}" will be permanently deleted from this '
                    'device. This cannot be undone.'
                : '${rows.length} songs will be permanently deleted from this '
                    'device. This cannot be undone.',
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Tip: Hide removes it from your library without deleting the file.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
