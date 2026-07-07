import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../state/library_actions.dart';
import 'add_to_playlist.dart';
import 'album_art.dart';

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: AlbumArt(artworkKey: meta.track.artworkKey, size: 48),
              title: Text(meta.track.title, maxLines: 1),
              subtitle: Text(meta.artistName.artistOrUnknown, maxLines: 1),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play next'),
              onTap: () =>
                  act(() => playNextMeta(ref, meta), 'Playing next'),
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
          ],
        ),
      );
    },
  );
}
