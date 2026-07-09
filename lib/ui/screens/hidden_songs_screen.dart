import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/tables.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

/// Settings › Hidden songs. Two sections — songs the user hid, and recordings
/// the junk filter auto-hid (with an explainer). Each row can be unhidden
/// permanently; each section has an "Unhide all".
class HiddenSongsScreen extends ConsumerWidget {
  const HiddenSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TrackWithMeta> byUser =
        ref.watch(hiddenByUserProvider).valueOrNull ?? const <TrackWithMeta>[];
    final List<TrackWithMeta> byFilter =
        ref.watch(hiddenByFilterProvider).valueOrNull ?? const <TrackWithMeta>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Hidden songs')),
      body: (byUser.isEmpty && byFilter.isEmpty)
          ? const _Empty()
          : ListView(
              children: <Widget>[
                if (byUser.isNotEmpty)
                  _Section(
                    title: 'Hidden by you',
                    tracks: byUser,
                    bucket: TrackVisibility.hiddenByUser,
                  ),
                if (byFilter.isNotEmpty)
                  _Section(
                    title: 'Auto-hidden recordings',
                    explainer:
                        'Voice notes, call recordings and ringtones we kept out '
                        'of your library. Unhide anything that\'s actually music.',
                    tracks: byFilter,
                    bucket: TrackVisibility.hiddenByFilter,
                  ),
                const SizedBox(height: Spacing.xl),
              ],
            ),
    );
  }
}

class _Section extends ConsumerWidget {
  const _Section({
    required this.title,
    required this.tracks,
    required this.bucket,
    this.explainer,
  });

  final String title;
  final List<TrackWithMeta> tracks;
  final TrackVisibility bucket;
  final String? explainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.lg, Spacing.sm, Spacing.xs),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => unhideAllInBucket(ref, bucket),
                child: const Text('Unhide all'),
              ),
            ],
          ),
        ),
        if (explainer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
            child: Text(
              explainer!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final TrackWithMeta meta in tracks)
          ListTile(
            leading: AlbumArt(artworkKey: meta.track.artworkKey, size: 44),
            title: Text(meta.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              meta.artistName.artistOrUnknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () => unhideTrack(ref, meta.track.id),
              child: const Text('Unhide'),
            ),
          ),
      ],
    );
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
            Icon(Icons.visibility_outlined,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.lg),
            Text('Nothing hidden', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text(
              'Songs you hide — and recordings we auto-hide — show up here.',
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
