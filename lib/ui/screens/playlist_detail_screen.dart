import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_names.dart';
import '../../core/format.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/daos/playlist_dao.dart';
import '../../data/db/viby_database.dart';
import '../../state/database_providers.dart';
import '../../state/library_actions.dart';
import '../../state/playlist_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/playlist_collage.dart';

/// Playlist detail: collage header, Play / Shuffle, and a reorderable,
/// swipe-to-remove track list. Rename / delete live in the AppBar menu.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow playlist,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: playlist.name);
    final String? raw = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final String? name = raw?.trim();
    if (name == null || name.isEmpty) return;
    await ref.read(vibyDatabaseProvider).playlistDao.renamePlaylist(
          playlist.id,
          name,
        );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow playlist,
  ) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text('“${playlist.name}” will be removed. '
                'The songs stay in your library.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await ref.read(vibyDatabaseProvider).playlistDao.deletePlaylist(playlist.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlaylistWithMeta?> detail =
        ref.watch(playlistDetailProvider(playlistId));
    final PlaylistWithMeta? pwm = detail.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(pwm?.playlist.name ?? 'Playlist'),
        actions: <Widget>[
          if (pwm != null)
            PopupMenuButton<String>(
              onSelected: (String value) {
                switch (value) {
                  case 'rename':
                    _rename(context, ref, pwm.playlist);
                  case 'delete':
                    _delete(context, ref, pwm.playlist);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
                PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (PlaylistWithMeta? data) {
          if (data == null) {
            return const Center(child: Text('Playlist not found.'));
          }
          final List<TrackWithMeta> tracks = data.tracks;
          final int totalMs = tracks.fold<int>(
            0,
            (int sum, TrackWithMeta m) => sum + m.track.durationMs,
          );
          return Column(
            children: <Widget>[
              _Header(
                playlist: data.playlist,
                artworkKeys: <String>[
                  for (final TrackWithMeta m in tracks)
                    if (m.track.artworkKey != null) m.track.artworkKey!,
                ],
                trackCount: tracks.length,
                totalMs: totalMs,
                onPlay: tracks.isEmpty ? null : () => playMetas(ref, tracks),
                onShuffle: tracks.isEmpty
                    ? null
                    : () => playMetas(ref, tracks, shuffle: true),
              ),
              const Divider(height: 1),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text('No songs yet. Add some from your library.'),
                      )
                    : _TrackList(playlistId: playlistId, tracks: tracks),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.playlist,
    required this.artworkKeys,
    required this.trackCount,
    required this.totalMs,
    required this.onPlay,
    required this.onShuffle,
  });

  final PlaylistRow playlist;
  final List<String> artworkKeys;
  final int trackCount;
  final int totalMs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String meta = <String>[
      '$trackCount ${trackCount == 1 ? 'song' : 'songs'}',
      if (totalMs > 0) formatTrackDuration(totalMs),
    ].join(' · ');

    // Collage keys are unique-ified for display (matches the grid card).
    final List<String> unique = <String>[];
    for (final String k in artworkKeys) {
      if (!unique.contains(k)) unique.add(k);
      if (unique.length >= 4) break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: <Widget>[
          PlaylistCollage(artworkKeys: unique, size: 180, borderRadius: 16),
          const SizedBox(height: 16),
          Text(
            playlist.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.playlistId, required this.tracks});

  final String playlistId;
  final List<TrackWithMeta> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaylistDao dao = ref.read(vibyDatabaseProvider).playlistDao;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      itemCount: tracks.length,
      onReorder: (int oldIndex, int newIndex) {
        final int to = newIndex > oldIndex ? newIndex - 1 : newIndex;
        dao.reorderEntry(playlistId: playlistId, from: oldIndex, to: to);
      },
      itemBuilder: (BuildContext context, int index) {
        final TrackWithMeta meta = tracks[index];
        // Position is dense (0..n-1) and the list is position-ordered, so the
        // list index is the entry position.
        return Dismissible(
          key: ValueKey<String>('${meta.track.id}@$index'),
          direction: DismissDirection.endToStart,
          background: ColoredBox(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.delete_outline,
                    color: scheme.onErrorContainer),
              ),
            ),
          ),
          onDismissed: (_) =>
              dao.removeEntry(playlistId: playlistId, position: index),
          child: ListTile(
            leading: AlbumArt(artworkKey: meta.track.artworkKey, size: 44),
            title: Text(meta.track.title, maxLines: 1),
            subtitle: Text(meta.artistName.artistOrUnknown, maxLines: 1),
            trailing: const Icon(Icons.drag_handle),
            onTap: () => playMetas(ref, tracks, startIndex: index),
          ),
        );
      },
    );
  }
}
