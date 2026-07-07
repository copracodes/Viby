import 'package:flutter/material.dart';

import 'album_art.dart';

/// A playlist's cover: a single art when the playlist draws on one album, a
/// 2×2 collage of up to four distinct album arts otherwise, and a placeholder
/// when it's empty. Missing quadrants fall back to the art placeholder.
class PlaylistCollage extends StatelessWidget {
  const PlaylistCollage({
    super.key,
    required this.artworkKeys,
    this.size = 56,
    this.borderRadius = 8,
  });

  /// Fills the bounded parent (e.g. an [Expanded] grid cell) instead of a
  /// fixed [size].
  const PlaylistCollage.expand({
    super.key,
    required this.artworkKeys,
    this.borderRadius = 8,
  }) : size = null;

  final List<String> artworkKeys;
  final double? size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (artworkKeys.isEmpty) return _single(null);
    if (artworkKeys.length == 1) return _single(artworkKeys.first);

    final Widget grid = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _grid(),
    );
    if (size != null) {
      return SizedBox(width: size, height: size, child: grid);
    }
    return grid;
  }

  Widget _single(String? key) => size != null
      ? AlbumArt(artworkKey: key, size: size, borderRadius: borderRadius)
      : AlbumArt.expand(artworkKey: key, borderRadius: borderRadius);

  Widget _grid() {
    Widget cell(int i) => Expanded(
          child: AlbumArt.expand(
            artworkKey: i < artworkKeys.length ? artworkKeys[i] : null,
            borderRadius: 0,
          ),
        );
    return Column(
      children: <Widget>[
        Expanded(child: Row(children: <Widget>[cell(0), cell(1)])),
        Expanded(child: Row(children: <Widget>[cell(2), cell(3)])),
      ],
    );
  }
}
