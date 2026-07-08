import 'package:flutter/material.dart';

import '../../core/display_names.dart';

/// A circular artist placeholder: up to two initials drawn on the scheme's
/// primary container. The single place an artist "portrait" is rendered (there's
/// no artist artwork source yet).
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
