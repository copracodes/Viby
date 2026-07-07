import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/daos/playlist_dao.dart';
import '../../state/database_providers.dart';
import '../../state/playlist_providers.dart';
import 'playlist_collage.dart';

/// Prompts for a playlist name. Returns the trimmed name, or null if cancelled
/// or left blank.
Future<String?> showNewPlaylistDialog(BuildContext context) async {
  final TextEditingController controller = TextEditingController();
  final String? raw = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (String v) => Navigator.of(ctx).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  final String? name = raw?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

/// Shows the new-playlist dialog and creates it, returning the new playlist id
/// (or null if cancelled).
Future<String?> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final String? name = await showNewPlaylistDialog(context);
  if (name == null) return null;
  return ref.read(vibyDatabaseProvider).playlistDao.createPlaylist(name);
}

/// Sheet for toggling a single track's membership across playlists (checkmarks
/// reflect current membership and update live as you tap).
Future<void> showAddTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  String trackId,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _AddTrackSheet(trackId: trackId),
  );
}

/// Sheet for adding many tracks (e.g. a whole album) to a chosen playlist.
Future<void> showAddTracksToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<String> trackIds, {
  required String label,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) =>
        _AddTracksSheet(trackIds: trackIds, label: label),
  );
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _NewPlaylistTile extends StatelessWidget {
  const _NewPlaylistTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.add)),
      title: const Text('New playlist'),
      onTap: onTap,
    );
  }
}

class _AddTrackSheet extends ConsumerWidget {
  const _AddTrackSheet({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlaylistSummary>> summaries =
        ref.watch(playlistSummariesProvider);
    final Set<String> containing =
        ref.watch(playlistIdsContainingProvider(trackId)).valueOrNull ??
            const <String>{};
    final PlaylistDao dao = ref.read(vibyDatabaseProvider).playlistDao;

    return _SheetScaffold(
      title: 'Add to playlist',
      child: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<PlaylistSummary> lists) => ListView(
          shrinkWrap: true,
          children: <Widget>[
            _NewPlaylistTile(
              onTap: () async {
                final String? id = await createPlaylistFlow(context, ref);
                if (id != null) await dao.toggleTrack(id, trackId);
              },
            ),
            const Divider(height: 1),
            for (final PlaylistSummary s in lists)
              CheckboxListTile(
                value: containing.contains(s.playlist.id),
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: PlaylistCollage(
                  artworkKeys: s.artworkKeys,
                  size: 44,
                  borderRadius: 6,
                ),
                title: Text(s.playlist.name, maxLines: 1),
                subtitle: Text('${s.trackCount} songs'),
                onChanged: (_) => dao.toggleTrack(s.playlist.id, trackId),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTracksSheet extends ConsumerWidget {
  const _AddTracksSheet({required this.trackIds, required this.label});

  final List<String> trackIds;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlaylistSummary>> summaries =
        ref.watch(playlistSummariesProvider);
    final PlaylistDao dao = ref.read(vibyDatabaseProvider).playlistDao;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    Future<void> addTo(String playlistId, String name) async {
      Navigator.of(context).pop();
      await dao.addTracks(playlistId, trackIds);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added ${trackIds.length} songs to $name'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    return _SheetScaffold(
      title: 'Add $label to playlist',
      child: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<PlaylistSummary> lists) => ListView(
          shrinkWrap: true,
          children: <Widget>[
            _NewPlaylistTile(
              onTap: () async {
                final String? id = await createPlaylistFlow(context, ref);
                if (id != null) {
                  await dao.addTracks(id, trackIds);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Added ${trackIds.length} songs'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            const Divider(height: 1),
            for (final PlaylistSummary s in lists)
              ListTile(
                leading: PlaylistCollage(
                  artworkKeys: s.artworkKeys,
                  size: 44,
                  borderRadius: 6,
                ),
                title: Text(s.playlist.name, maxLines: 1),
                subtitle: Text('${s.trackCount} songs'),
                onTap: () => addTo(s.playlist.id, s.playlist.name),
              ),
          ],
        ),
      ),
    );
  }
}
