import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_names.dart';
import '../../core/router.dart';
import 'album_art.dart';

/// A single album cell (art + name + artist) for the albums grid on the Library
/// tab and artist detail. Tapping opens album detail.
class AlbumGridCell extends StatelessWidget {
  const AlbumGridCell({
    super.key,
    required this.albumId,
    required this.artworkKey,
    required this.name,
    required this.artistName,
  });

  final String albumId;
  final String? artworkKey;
  final String name;
  final String? artistName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(AppRoutes.album(albumId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: AlbumArt.expand(artworkKey: artworkKey, borderRadius: 10),
          ),
          const SizedBox(height: 6),
          Text(
            name.albumOrUnknown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            artistName.artistOrUnknown,
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

/// The grid delegate shared by every 2-column album grid.
const SliverGridDelegate kAlbumGridDelegate =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
  childAspectRatio: 0.78,
);
