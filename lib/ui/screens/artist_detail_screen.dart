import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/viby_database.dart';
import '../../state/database_providers.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../widgets/album_grid_cell.dart';

/// Artist detail: a header with a "play all" / "shuffle all" action over the
/// artist's tracks, and their albums as a grid.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artistId});

  final String artistId;

  Future<void> _playAll(WidgetRef ref, {bool shuffle = false}) async {
    final List<TrackWithMeta> metas = await ref
        .read(vibyDatabaseProvider)
        .libraryDao
        .getTracksByArtist(artistId);
    await playMetas(ref, metas, shuffle: shuffle);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ArtistWithAlbums?> detail =
        ref.watch(artistDetailProvider(artistId));
    return Scaffold(
      appBar: AppBar(),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (ArtistWithAlbums? awa) {
          if (awa == null) {
            return const Center(child: Text('Artist not found.'));
          }
          final List<AlbumRow> albums = awa.albums;
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Header(
                  name: awa.artist.name,
                  albumCount: albums.length,
                  onPlay: () => _playAll(ref),
                  onShuffle: () => _playAll(ref, shuffle: true),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.builder(
                  gridDelegate: kAlbumGridDelegate,
                  itemCount: albums.length,
                  itemBuilder: (BuildContext context, int i) => AlbumGridCell(
                    albumId: albums[i].id,
                    artworkKey: albums[i].artworkKey,
                    name: albums[i].name,
                    artistName: awa.artist.name,
                  ),
                ),
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
    required this.name,
    required this.albumCount,
    required this.onPlay,
    required this.onShuffle,
  });

  final String name;
  final int albumCount;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(name.artistOrUnknown, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play all'),
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
