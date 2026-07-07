import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/viby_database.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/album_art.dart';
import '../widgets/track_tile.dart';

/// Album detail: header (art, title, artist, year, track count), Play / Shuffle,
/// and the track list. Tapping a row plays the album from that track.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AlbumWithTracks?> detail =
        ref.watch(albumDetailProvider(albumId));
    final AlbumWithTracks? current = detail.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          if (current != null && current.tracks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add to playlist',
              onPressed: () => showAddTracksToPlaylist(
                context,
                ref,
                current.tracks.map((TrackRow t) => t.id).toList(),
                label: current.album.name.albumOrUnknown,
              ),
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (AlbumWithTracks? awt) {
          if (awt == null) {
            return const Center(child: Text('Album not found.'));
          }
          final AlbumRow album = awt.album;
          final String? artistName =
              ref.watch(artistProvider(album.artistId)).valueOrNull?.name;
          final List<TrackWithMeta> metas = awt.tracks
              .map(
                (TrackRow r) => TrackWithMeta(
                  track: r,
                  albumName: album.name,
                  artistName: artistName,
                ),
              )
              .toList();

          return ListView.builder(
            itemCount: metas.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return _Header(
                  album: album,
                  artistName: artistName,
                  trackCount: metas.length,
                  onPlay: () => playMetas(ref, metas),
                  onShuffle: () => playMetas(ref, metas, shuffle: true),
                );
              }
              final int i = index - 1;
              final TrackRow row = metas[i].track;
              return TrackTile(
                meta: metas[i],
                trackNumber: row.trackNo > 0 ? row.trackNo : i + 1,
                onTap: () => playMetas(ref, metas, startIndex: i),
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.album,
    required this.artistName,
    required this.trackCount,
    required this.onPlay,
    required this.onShuffle,
  });

  final AlbumRow album;
  final String? artistName;
  final int trackCount;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String meta = <String>[
      if (album.year != null) '${album.year}',
      '$trackCount ${trackCount == 1 ? 'song' : 'songs'}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: <Widget>[
          AlbumArt(artworkKey: album.artworkKey, size: 200, borderRadius: 16),
          const SizedBox(height: 16),
          Text(
            album.name.albumOrUnknown,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            artistName.artistOrUnknown,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary),
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
