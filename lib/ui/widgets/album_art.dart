import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/sources/local/artwork_service.dart';
import '../../state/library_providers.dart';

/// Square album artwork loaded from the on-disk cache, with a themed
/// music-note placeholder when there's no key, the directory isn't ready, or
/// the file is missing/unreadable. The single place art is rendered.
class AlbumArt extends ConsumerWidget {
  const AlbumArt({
    super.key,
    required this.artworkKey,
    this.size = 56,
    this.borderRadius = 8,
    this.decodeSize = 512,
  });

  /// Fills the bounded parent (e.g. an [Expanded] in a grid cell) instead of a
  /// fixed [size].
  const AlbumArt.expand({
    super.key,
    required this.artworkKey,
    this.borderRadius = 8,
    this.decodeSize = 512,
  }) : size = null;

  final String? artworkKey;
  final double? size;
  final double borderRadius;

  /// Upper bound (logical px) used to compute the decode resolution, so a 600px
  /// source isn't held in the image cache at full size behind a 48px thumbnail.
  /// Multiplied by the device pixel ratio for the actual `cacheWidth`.
  final double decodeSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BorderRadius radius = BorderRadius.circular(borderRadius);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? key = artworkKey;
    final Directory? dir =
        key == null ? null : ref.watch(artworkDirectoryProvider).valueOrNull;

    Widget content;
    if (key == null || dir == null) {
      content = _placeholder(scheme, radius);
    } else {
      final File file = File(p.join(dir.path, ArtworkService.fileNameFor(key)));
      // Decode to roughly display resolution: a 48px thumbnail doesn't need the
      // full 600px source in memory — decisive for smooth 10k-track scrolling.
      final double dpr = MediaQuery.devicePixelRatioOf(context);
      final double target = size ?? decodeSize;
      final int cacheWidth = (target * dpr).round().clamp(1, 2048);
      content = ClipRRect(
        borderRadius: radius,
        child: Image.file(
          file,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => _placeholder(scheme, radius),
        ),
      );
    }

    if (size != null) {
      return SizedBox(width: size, height: size, child: content);
    }
    return content; // expand: the caller bounds it (Expanded / AspectRatio).
  }

  Widget _placeholder(ColorScheme scheme, BorderRadius radius) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double side = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : (size ?? 56);
          return Center(
            child: Icon(
              Icons.music_note,
              size: side * 0.5,
              color: scheme.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}
