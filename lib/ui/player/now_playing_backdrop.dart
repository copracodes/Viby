import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/sources/local/artwork_service.dart';
import '../../state/library_providers.dart';

/// The Now Playing backdrop: the current artwork blurred heavily, under a scrim
/// tinted with the scheme surface. Wrapped in a [RepaintBoundary] and depending
/// only on the artwork key + scheme (never on the position stream), so it is
/// rasterised once and cheaply re-composited as the transition opacity animates
/// — the acceptance-bar "don't rebuild the backdrop on position ticks".
class NowPlayingBackdrop extends ConsumerWidget {
  const NowPlayingBackdrop({super.key, required this.artworkKey});

  final String? artworkKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? key = artworkKey;
    final Directory? dir =
        key == null ? null : ref.watch(artworkDirectoryProvider).valueOrNull;

    Widget image;
    if (key == null || dir == null) {
      image = ColoredBox(color: scheme.surface);
    } else {
      final File file =
          File(p.join(dir.path, ArtworkService.fileNameFor(key)));
      image = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // The blur hides detail, so decode small — cheap raster, big blur.
        cacheWidth: 96,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => ColoredBox(color: scheme.surface),
      );
    }

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: image,
          ),
          // Scrim: surface at ~70% keeps text legible over any artwork and ties
          // the backdrop to the (dynamic) scheme.
          ColoredBox(color: scheme.surface.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}
