import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../core/format.dart';
import '../../data/db/daos/library_dao.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import 'album_art.dart';
import 'equalizer_bars.dart';
import 'track_actions_sheet.dart';

/// A single track row used by the Tracks tab, album detail and search.
///
/// Pass [trackNumber] (album detail) to show a number instead of artwork; else
/// it shows the album art. Long-press always opens the actions sheet.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.meta,
    required this.onTap,
    this.trackNumber,
    this.showArt = true,
    this.selected = false,
  });

  final TrackWithMeta meta;
  final VoidCallback onTap;
  final int? trackNumber;
  final bool showArt;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Only the (few) visible rows watch this; it re-fires just when the current
    // track changes, so it's cheap even in the 10k Tracks tab.
    final bool isCurrent = ref.watch(
      queueControllerProvider
          .select((QueueState q) => q.currentTrack?.id == meta.track.id),
    );
    final bool playing =
        isCurrent && (ref.watch(playingProvider).valueOrNull ?? false);

    Widget? leading;
    if (trackNumber != null) {
      leading = SizedBox(
        width: 36,
        child: Center(
          child: isCurrent
              ? EqualizerBars(playing: playing, size: 16)
              : Text(
                  '$trackNumber',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
      );
    } else if (showArt) {
      leading = AlbumArt(artworkKey: meta.track.artworkKey, size: 48);
    }

    return ListTile(
      selected: selected,
      leading: leading,
      title: Text(
        meta.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent
            ? theme.textTheme.bodyLarge?.copyWith(color: scheme.primary)
            : null,
      ),
      subtitle: Text(
        meta.artistName.artistOrUnknown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: (isCurrent && trackNumber == null)
          ? EqualizerBars(playing: playing, size: 18)
          : Text(
              formatTrackDuration(meta.track.durationMs),
              style: theme.textTheme.bodySmall,
            ),
      onTap: onTap,
      onLongPress: () => showTrackActions(context, ref, meta),
    );
  }
}
