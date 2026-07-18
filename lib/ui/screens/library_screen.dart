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
import '../library/fast_scroll.dart';
import '../theme/tokens.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/album_grid_cell.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/playlist_collage.dart';
import '../widgets/stagger.dart';
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
      builder: (List<AlbumWithArtist> albums) => StaggerScope(
        child: GridView.builder(
          padding: const EdgeInsets.all(Spacing.md),
          gridDelegate: kAlbumGridDelegate,
          itemCount: albums.length,
          itemBuilder: (BuildContext context, int i) => StaggeredEntrance(
            index: i,
            child: AlbumGridCell(
              albumId: albums[i].album.id,
              artworkKey: albums[i].album.artworkKey,
              name: albums[i].album.name,
              artistName: albums[i].artistName,
            ),
          ),
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
            leading: ArtistArt(
              artistId: artist.id,
              name: artist.name,
              radius: 20,
            ),
            title: Text(artist.name.artistOrUnknown, maxLines: 1),
            onTap: () => context.push(AppRoutes.artist(artist.id)),
          );
        },
      ),
    );
  }
}

class _TracksTab extends ConsumerStatefulWidget {
  const _TracksTab();

  @override
  ConsumerState<_TracksTab> createState() => _TracksTabState();
}

class _TracksTabState extends ConsumerState<_TracksTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int hiddenCount = ref.watch(hiddenTrackCountProvider).valueOrNull ?? 0;
    return _AsyncList<TrackWithMeta>(
      value: ref.watch(allTracksProvider),
      emptyLabel: 'No tracks yet.',
      builder: (List<TrackWithMeta> tracks) => Column(
        children: <Widget>[
          Expanded(
            child: FastScrollbar(
              controller: _scrollController,
              labels: tracks.map((TrackWithMeta t) => t.track.title).toList(),
              child: ListView.builder(
                controller: _scrollController,
                // Fixed two-line ListTile height → O(1) scroll over 10k rows.
                itemExtent: 64,
                itemCount: tracks.length,
                itemBuilder: (BuildContext context, int i) => TrackTile(
                  meta: tracks[i],
                  onTap: () => playMetas(ref, tracks, startIndex: i),
                ),
              ),
            ),
          ),
          if (hiddenCount > 0) _HiddenFooter(count: hiddenCount),
        ],
      ),
    );
  }
}

/// End-of-list row linking to the Hidden-songs manager (only when > 0 hidden).
class _HiddenFooter extends StatelessWidget {
  const _HiddenFooter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => context.push(AppRoutes.hidden),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.visibility_off_outlined,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  '$count hidden ${count == 1 ? 'song' : 'songs'}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Text('View',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
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
            // The virtual "Liked Songs" collection is always pinned first, then
            // the user's playlists.
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: kAlbumGridDelegate,
              itemCount: playlists.length + 1,
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? const _LikedSongsCard()
                  : _PlaylistCard(summary: playlists[i - 1]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned "Liked Songs" collection card (filled-heart cover + live count).
class _LikedSongsCard extends ConsumerWidget {
  const _LikedSongsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int count = ref.watch(likedCountProvider).valueOrNull ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(AppRoutes.liked),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
              ),
              child: Center(
                child: Icon(Icons.favorite,
                    size: 48, color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Liked Songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          Text(
            '$count ${count == 1 ? 'song' : 'songs'}',
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
