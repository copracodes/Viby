import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/tables.dart';
import '../../data/db/viby_database.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import 'add_to_playlist.dart';
import 'album_art.dart';
import 'delete_from_device.dart';
import 'like_button.dart';

/// Long-press actions for a track row.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  TrackWithMeta meta,
) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      void act(Future<void> Function() action, String toast) {
        Navigator.of(sheetContext).pop();
        action();
        messenger.showSnackBar(
          SnackBar(content: Text(toast), duration: const Duration(seconds: 2)),
        );
      }

      return SafeArea(
        // Scrollable: the sheet is capped at a fraction of the screen, and with
        // the subtitled rows it can outgrow that on a short display.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: AlbumArt(artworkKey: meta.track.artworkKey, size: 48),
                title: Text(meta.track.title, maxLines: 1),
                subtitle: Text(meta.artistName.artistOrUnknown, maxLines: 1),
                trailing: LikeButton(trackId: meta.track.id),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Play next'),
                onTap: () => act(() => playNextMeta(ref, meta), 'Playing next'),
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to queue'),
                onTap: () =>
                    act(() => addMetaToQueue(ref, meta), 'Added to queue'),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to playlist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showAddTrackToPlaylist(context, ref, meta.track.id);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide song'),
                subtitle: const Text('Keeps the file on your device'),
                onTap: () =>
                    act(() => hideTrack(ref, meta.track.id), 'Song hidden'),
              ),
              // Deliberately set apart from Hide, in the error colour: the two
              // sit next to each other and one of them is irreversible.
              if (_canDelete(ref, meta.track)) ...<Widget>[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Delete from device',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  subtitle: const Text('Removes the file permanently'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showDeleteFromDevice(context, ref, <TrackRow>[meta.track]);
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Whether this row may be deleted from the device: the platform can delete, and
/// the track is a local, MediaStore-backed file (never a Subsonic pointer).
bool _canDelete(WidgetRef ref, TrackRow track) =>
    ref.read(mediaDeleterProvider).capable && track.source == TrackSource.local;
