import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../state/library_providers.dart';
import 'album_art.dart';

/// An artist portrait: the derived artwork of the artist's most-played album
/// ([artistArtworkProvider]), circular-cropped, falling back to the letter
/// [ArtistAvatar] when the artist has no album art. The single place an artist
/// portrait is resolved.
class ArtistArt extends ConsumerWidget {
  const ArtistArt({
    super.key,
    required this.artistId,
    required this.name,
    this.radius = 24,
  });

  final String artistId;

  /// The raw artist name (for the letter fallback; `<unknown>`/null handled).
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? key =
        ref.watch(artistArtworkProvider(artistId)).valueOrNull;
    if (key == null) return ArtistAvatar(name: name, radius: radius);
    // A square AlbumArt with a half-side corner radius reads as a circle, and
    // reuses its shimmer/fade/placeholder handling.
    return AlbumArt(
      artworkKey: key,
      size: radius * 2,
      borderRadius: radius,
    );
  }
}

/// A circular artist placeholder: up to two initials drawn on the scheme's
/// primary container. The letter fallback behind [ArtistArt].
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.name, this.radius = 24});

  /// The raw artist name (MediaStore `<unknown>` / null handled internally).
  final String? name;
  final double radius;

  static String initialsOf(String display) {
    final List<String> words = display
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String display = name.artistOrUnknown;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initialsOf(display),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
