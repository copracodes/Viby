import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/loop_region.dart';
import '../../state/ab_loop_provider.dart';
import '../../state/player_providers.dart';
import '../theme/tokens.dart';

/// The Now Playing scrubber: an [audio_video_progress_bar] themed to the current
/// (dynamic) scheme — played = primary, buffered = primary @ 30% — with a time
/// bubble that appears above the thumb while scrubbing.
class PlayerProgress extends ConsumerStatefulWidget {
  const PlayerProgress({super.key});

  @override
  ConsumerState<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends ConsumerState<PlayerProgress> {
  Duration? _scrubTime;
  double? _scrubX;

  void _onDrag(ThumbDragDetails d) {
    setState(() {
      _scrubTime = d.timeStamp;
      _scrubX = d.localPosition.dx;
    });
  }

  void _endScrub() => setState(() {
        _scrubTime = null;
        _scrubX = null;
      });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final Duration buffered =
        ref.watch(bufferedPositionProvider).valueOrNull ?? Duration.zero;
    final Duration total =
        ref.watch(trackDurationProvider).valueOrNull ?? Duration.zero;
    final AbLoopState ab = ref.watch(abLoopControllerProvider);
    final LoopRegion? region = ab is AbLoopArmed ? ab.region : null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            ProgressBar(
              progress: position,
              buffered: buffered,
              total: total,
              onSeek: (Duration d) => ref.read(playerServiceProvider).seek(d),
              onDragStart: _onDrag,
              onDragUpdate: _onDrag,
              onDragEnd: _endScrub,
              barHeight: 4,
              thumbRadius: 7,
              thumbGlowRadius: 18,
              progressBarColor: scheme.primary,
              thumbColor: scheme.primary,
              bufferedBarColor: scheme.primary.withValues(alpha: 0.3),
              baseBarColor: scheme.onSurface.withValues(alpha: 0.15),
              timeLabelTextStyle: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            // The armed A–B span, drawn over the bar line (labels sit below, so
            // the bar zone is the top 14px — see `_kBarZoneHeight`).
            if (region != null && total.inMilliseconds > 0)
              Positioned(
                left: 0,
                top: 0,
                width: constraints.maxWidth,
                height: _kBarZoneHeight,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _LoopRegionPainter(
                      aFraction:
                          (region.aMs / total.inMilliseconds).clamp(0.0, 1.0),
                      bFraction:
                          (region.bMs / total.inMilliseconds).clamp(0.0, 1.0),
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            if (_scrubTime != null && _scrubX != null)
              _ScrubBubble(
                time: _scrubTime!,
                x: _scrubX!.clamp(0.0, constraints.maxWidth),
                scheme: scheme,
              ),
          ],
        );
      },
    );
  }
}

/// The vertical extent (logical px) the progress bar's line + thumb occupy at
/// the top of the widget, before the time labels: `max(2 * thumbRadius,
/// barHeight)` with the values passed to [ProgressBar] above.
const double _kBarZoneHeight = 14;

/// Paints the A–B loop span: a subtle low-alpha primary band between two thin
/// full-height markers, aligned to the bar line.
class _LoopRegionPainter extends CustomPainter {
  const _LoopRegionPainter({
    required this.aFraction,
    required this.bFraction,
    required this.color,
  });

  final double aFraction;
  final double bFraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double ax = aFraction * size.width;
    final double bx = bFraction * size.width;
    const double barHeight = 4;
    final double barTop = (size.height - barHeight) / 2;

    // The highlighted span, sitting on the bar line.
    final Paint band = Paint()..color = color.withValues(alpha: 0.28);
    canvas.drawRect(
      Rect.fromLTRB(ax, barTop, bx, barTop + barHeight),
      band,
    );

    // Two small markers at A and B, spanning the full bar zone.
    final Paint marker = Paint()..color = color.withValues(alpha: 0.9);
    for (final double x in <double>[ax, bx]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x.clamp(0.0, size.width - 2), 0, 2, size.height),
          const Radius.circular(1),
        ),
        marker,
      );
    }
  }

  @override
  bool shouldRepaint(_LoopRegionPainter old) =>
      old.aFraction != aFraction ||
      old.bFraction != bFraction ||
      old.color != color;
}

class _ScrubBubble extends StatelessWidget {
  const _ScrubBubble({
    required this.time,
    required this.x,
    required this.scheme,
  });

  final Duration time;
  final double x;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    const double width = 56;
    return Positioned(
      top: -34,
      left: (x - width / 2).clamp(0.0, double.infinity),
      child: Container(
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: Radii.brSm,
        ),
        child: Text(
          _fmt(time),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: scheme.onPrimary),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }
}
