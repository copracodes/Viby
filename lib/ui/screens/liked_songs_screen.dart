import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

/// The virtual "Liked Songs" collection — liked tracks, newest first. Not a real
/// playlist: no rename/delete/reorder. Play / Shuffle, and swipe a row to unlike.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TrackWithMeta> tracks =
        ref.watch(likedTracksProvider).valueOrNull ?? const <TrackWithMeta>[];
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Liked Songs')),
      body: tracks.isEmpty
          ? const _Empty()
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: _Header(count: tracks.length)),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int i) {
                      final TrackWithMeta meta = tracks[i];
                      return Dismissible(
                        key: ValueKey<String>(meta.track.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) =>
                            setTrackLiked(ref, meta.track.id, false),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: Spacing.lg),
                          color: theme.colorScheme.errorContainer,
                          child: Icon(Icons.heart_broken,
                              color: theme.colorScheme.onErrorContainer),
                        ),
                        child: ListTile(
                          leading:
                              AlbumArt(artworkKey: meta.track.artworkKey, size: 44),
                          title: Text(meta.track.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(meta.artistName.artistOrUnknown,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => playMetas(ref, tracks, startIndex: i),
                        ),
                      );
                    },
                    childCount: tracks.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
              ],
            ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        children: <Widget>[
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: Radii.brLg,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  theme.colorScheme.primary,
                  theme.colorScheme.tertiary,
                ],
              ),
            ),
            child: Icon(Icons.favorite,
                size: 64, color: theme.colorScheme.onPrimary),
          ),
          const SizedBox(height: Spacing.md),
          Text('$count ${count == 1 ? 'song' : 'songs'}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => _play(ref),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              const SizedBox(width: Spacing.md),
              FilledButton.tonalIcon(
                onPressed: () => _play(ref, shuffle: true),
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _play(WidgetRef ref, {bool shuffle = false}) {
    final List<TrackWithMeta> tracks =
        ref.read(likedTracksProvider).valueOrNull ?? const <TrackWithMeta>[];
    if (tracks.isEmpty) return;
    playMetas(ref, tracks, shuffle: shuffle);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.favorite_border,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.lg),
            Text('No liked songs yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text(
              'Tap the heart on any song to add it here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
