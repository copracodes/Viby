import 'package:flutter/material.dart';

/// Pure helpers for the alphabet fast-scroll thumb (essential at 10k tracks).
/// Kept free of widget state so the letter/index math is unit-testable.

/// The A–Z bucket a display name sorts under: its first Latin letter,
/// uppercased. Names starting with a digit, symbol, whitespace, or a non-Latin
/// script bucket under '#'.
String bucketLetter(String name) {
  final String trimmed = name.trimLeft();
  if (trimmed.isEmpty) return '#';
  final String first = trimmed[0].toUpperCase();
  final int code = first.codeUnitAt(0);
  if (code >= 0x41 && code <= 0x5A) return first; // A..Z
  return '#';
}

/// Maps a drag [fraction] (0..1 down the track) to a list index in [0, count).
int indexForFraction(int count, double fraction) {
  if (count <= 0) return 0;
  final int i = (fraction.clamp(0.0, 1.0) * count).floor();
  return i.clamp(0, count - 1);
}

/// The bucket letter shown for a drag [fraction] over [names] (already sorted).
/// Empty list → '#'.
String letterForFraction(List<String> names, double fraction) {
  if (names.isEmpty) return '#';
  return bucketLetter(names[indexForFraction(names.length, fraction)]);
}

/// A draggable vertical scrollbar that shows the current alphabet bucket in a
/// bubble while dragging, and jumps [controller] to the matching offset. Wrap a
/// scroll view with this in a Stack. [labels] is the ordered list of the items'
/// display names (used only for the bubble letter).
class FastScrollbar extends StatefulWidget {
  const FastScrollbar({
    super.key,
    required this.controller,
    required this.labels,
    required this.child,
  });

  final ScrollController controller;
  final List<String> labels;
  final Widget child;

  @override
  State<FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<FastScrollbar> {
  bool _dragging = false;
  double _thumbFraction = 0;

  void _jumpTo(double fraction, double trackHeight) {
    setState(() {
      _dragging = true;
      _thumbFraction = fraction.clamp(0.0, 1.0);
    });
    final ScrollController c = widget.controller;
    if (c.hasClients) {
      c.jumpTo(c.position.maxScrollExtent * _thumbFraction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight;
        return Stack(
          children: <Widget>[
            widget.child,
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 32,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (DragStartDetails d) =>
                    _jumpTo(d.localPosition.dy / height, height),
                onVerticalDragUpdate: (DragUpdateDetails d) =>
                    _jumpTo(d.localPosition.dy / height, height),
                onVerticalDragEnd: (_) => setState(() => _dragging = false),
                child: const SizedBox.expand(),
              ),
            ),
            if (_dragging)
              Positioned(
                right: 40,
                top: (_thumbFraction * height - 28).clamp(0.0, height - 56),
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: Text(
                        letterForFraction(widget.labels, _thumbFraction),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimary,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
