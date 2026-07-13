import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/viby_database.dart';
import '../../data/sources/local/delete_targets.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/album_art.dart';
import '../widgets/delete_from_device.dart';
import '../widgets/track_tile.dart';

/// Album detail: a collapsing header (large art + title that fold into a compact
/// AppBar), a Play / Shuffle pair, and the track list. Tapping a row plays the
/// album from that track; the currently-playing row shows the equalizer.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  final ScrollController _controller = ScrollController();
  static const double _expandedHeight = 360;
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

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AlbumWithTracks?> detail =
        ref.watch(albumDetailProvider(widget.albumId));

    return Scaffold(
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
              .map((TrackRow r) => TrackWithMeta(
                    track: r,
                    albumName: album.name,
                    artistName: artistName,
                  ))
              .toList();

          return CustomScrollView(
            controller: _controller,
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: _expandedHeight,
                title: AnimatedOpacity(
                  opacity: _collapsed ? 1 : 0,
                  duration: Motion.fast,
                  child: Text(album.name.albumOrUnknown),
                ),
                actions: <Widget>[
                  if (metas.isNotEmpty)
                    _AlbumOverflow(
                      album: album,
                      metas: metas,
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _HeaderArt(
                    artworkKey: album.artworkKey,
                    name: album.name,
                    artistName: artistName,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Actions(
                  album: album,
                  trackCount: metas.length,
                  onPlay: () => playMetas(ref, metas),
                  onShuffle: () => playMetas(ref, metas, shuffle: true),
                ),
              ),
              SliverList.builder(
                itemCount: metas.length,
                itemBuilder: (BuildContext context, int i) => TrackTile(
                  meta: metas[i],
                  trackNumber:
                      metas[i].track.trackNo > 0 ? metas[i].track.trackNo : i + 1,
                  onTap: () => playMetas(ref, metas, startIndex: i),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
            ],
          );
        },
      ),
    );
  }
}

/// Album-level actions. "Delete album from device" lives here — behind an
/// overflow, in the error colour, never one tap away — and covers the whole album
/// in a single platform delete request (one system dialog for the batch).
class _AlbumOverflow extends ConsumerWidget {
  const _AlbumOverflow({required this.album, required this.metas});

  final AlbumRow album;
  final List<TrackWithMeta> metas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<TrackRow> rows =
        metas.map((TrackWithMeta m) => m.track).toList();
    final DeleteTargets targets = resolveDeleteTargets(rows);
    final bool canDelete =
        ref.watch(mediaDeleterProvider).capable && !targets.isEmpty;

    return PopupMenuButton<String>(
      onSelected: (String value) {
        switch (value) {
          case 'playlist':
            showAddTracksToPlaylist(
              context,
              ref,
              rows.map((TrackRow t) => t.id).toList(),
              label: album.name.albumOrUnknown,
            );
          case 'delete':
            showDeleteFromDevice(context, ref, rows);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'playlist',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_add),
            title: Text('Add to playlist'),
          ),
        ),
        if (canDelete) ...<PopupMenuEntry<String>>[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(
                'Delete album from device',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(
                'Removes ${targets.length} '
                '${targets.length == 1 ? 'file' : 'files'} permanently',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The expanded-header content: the album art centred over a soft scrim.
class _HeaderArt extends StatelessWidget {
  const _HeaderArt({
    required this.artworkKey,
    required this.name,
    required this.artistName,
  });

  final String? artworkKey;
  final String name;
  final String? artistName;

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
              Expanded(
                child: AlbumArt.expand(
                  artworkKey: artworkKey,
                  borderRadius: Radii.lg,
                  outline: true,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                name.albumOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                artistName.artistOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.album,
    required this.trackCount,
    required this.onPlay,
    required this.onShuffle,
  });

  final AlbumRow album;
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
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            meta,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: FilledButton.tonalIcon(
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
