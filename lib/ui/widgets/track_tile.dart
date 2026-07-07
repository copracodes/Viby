import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../core/format.dart';
import '../../data/db/daos/library_dao.dart';
import 'album_art.dart';
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

    Widget? leading;
    if (trackNumber != null) {
      leading = SizedBox(
        width: 36,
        child: Center(
          child: Text(
            '$trackNumber',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
      ),
      subtitle: Text(
        meta.artistName.artistOrUnknown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatTrackDuration(meta.track.durationMs),
        style: theme.textTheme.bodySmall,
      ),
      onTap: onTap,
      onLongPress: () => showTrackActions(context, ref, meta),
    );
  }
}
