import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/viby_database.dart';
import '../../state/database_providers.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/album_grid_cell.dart';
import '../widgets/artist_avatar.dart';

/// Artist detail: a collapsing header (large circular avatar + name folding into
/// a compact AppBar), a Play all / Shuffle pair, and the artist's albums grid.
class ArtistDetailScreen extends ConsumerStatefulWidget {
  const ArtistDetailScreen({super.key, required this.artistId});

  final String artistId;

  @override
  ConsumerState<ArtistDetailScreen> createState() =>
      _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends ConsumerState<ArtistDetailScreen> {
  final ScrollController _controller = ScrollController();
  static const double _expandedHeight = 280;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final double top = MediaQuery.paddingOf(context).top;
    final bool collapsed =
        _controller.offset > _expandedHeight - kToolbarHeight - top;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _playAll({bool shuffle = false}) async {
    final List<TrackWithMeta> metas = await ref
        .read(vibyDatabaseProvider)
        .libraryDao
        .getTracksByArtist(widget.artistId);
    await playMetas(ref, metas, shuffle: shuffle);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ArtistWithAlbums?> detail =
        ref.watch(artistDetailProvider(widget.artistId));
    return Scaffold(
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (ArtistWithAlbums? awa) {
          if (awa == null) {
            return const Center(child: Text('Artist not found.'));
          }
          final List<AlbumRow> albums = awa.albums;
          return CustomScrollView(
            controller: _controller,
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: _expandedHeight,
                title: AnimatedOpacity(
                  opacity: _collapsed ? 1 : 0,
                  duration: Motion.fast,
                  child: Text(awa.artist.name.artistOrUnknown),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _HeaderArt(
                    name: awa.artist.name,
                    albumCount: albums.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _playAll(),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play all'),
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _playAll(shuffle: true),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.md),
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

class _HeaderArt extends StatelessWidget {
  const _HeaderArt({required this.name, required this.albumCount});

  final String name;
  final int albumCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            theme.colorScheme.surfaceContainerHigh,
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.xxxl, Spacing.lg, Spacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              ArtistAvatar(name: name, radius: 52),
              const SizedBox(height: Spacing.md),
              Text(
                name.artistOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              Text(
                '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
