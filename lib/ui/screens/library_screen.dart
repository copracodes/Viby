import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_names.dart';
import '../../core/router.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/daos/playlist_dao.dart';
import '../../data/db/viby_database.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../../state/playlist_providers.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/album_grid_cell.dart';
import '../widgets/playlist_collage.dart';
import '../widgets/track_tile.dart';

/// Library: Albums | Artists | Tracks | Playlists.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
              Tab(text: 'Tracks'),
              Tab(text: 'Playlists'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _AlbumsTab(),
            _ArtistsTab(),
            _TracksTab(),
            _PlaylistsTab(),
          ],
        ),
      ),
    );
  }
}

/// Shared async-list scaffolding: spinner / error / empty / builder.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.emptyLabel,
    required this.builder,
  });

  final AsyncValue<List<T>> value;
  final String emptyLabel;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (List<T> items) =>
          items.isEmpty ? Center(child: Text(emptyLabel)) : builder(items),
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncList<AlbumWithArtist>(
      value: ref.watch(albumsProvider),
      emptyLabel: 'No albums yet.',
      builder: (List<AlbumWithArtist> albums) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: kAlbumGridDelegate,
        itemCount: albums.length,
        itemBuilder: (BuildContext context, int i) => AlbumGridCell(
          albumId: albums[i].album.id,
          artworkKey: albums[i].album.artworkKey,
          name: albums[i].album.name,
          artistName: albums[i].artistName,
        ),
      ),
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncList<ArtistRow>(
      value: ref.watch(artistsProvider),
      emptyLabel: 'No artists yet.',
      builder: (List<ArtistRow> artists) => ListView.builder(
        // Uniform row height → skip per-item layout for jank-free long lists.
        itemExtent: 56,
        itemCount: artists.length,
        itemBuilder: (BuildContext context, int i) {
          final ArtistRow artist = artists[i];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(artist.name.artistOrUnknown, maxLines: 1),
            onTap: () => context.push(AppRoutes.artist(artist.id)),
          );
        },
      ),
    );
  }
}

class _TracksTab extends ConsumerWidget {
  const _TracksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncList<TrackWithMeta>(
      value: ref.watch(allTracksProvider),
      emptyLabel: 'No tracks yet.',
      builder: (List<TrackWithMeta> tracks) => ListView.builder(
        // Fixed two-line ListTile height → constant-time scroll over 10k rows.
        itemExtent: 64,
        itemCount: tracks.length,
        itemBuilder: (BuildContext context, int i) => TrackTile(
          meta: tracks[i],
          onTap: () => playMetas(ref, tracks, startIndex: i),
        ),
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final String? id = await createPlaylistFlow(context, ref);
    if (id != null && context.mounted) context.push(AppRoutes.playlist(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncList<PlaylistSummary>(
      value: ref.watch(playlistSummariesProvider),
      // Empty is handled below (we still want the create button visible).
      emptyLabel: '',
      builder: (List<PlaylistSummary> playlists) => Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: FilledButton.tonalIcon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New playlist'),
              ),
            ),
          ),
          Expanded(
            child: playlists.isEmpty
                ? const Center(child: Text('No playlists yet.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: kAlbumGridDelegate,
                    itemCount: playlists.length,
                    itemBuilder: (BuildContext context, int i) =>
                        _PlaylistCard(summary: playlists[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.summary});

  final PlaylistSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(AppRoutes.playlist(summary.playlist.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: PlaylistCollage.expand(
              artworkKeys: summary.artworkKeys,
              borderRadius: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary.playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '${summary.trackCount} ${summary.trackCount == 1 ? 'song' : 'songs'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
