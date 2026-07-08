import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
