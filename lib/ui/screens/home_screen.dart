import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../state/player_providers.dart';

/// Home screen for the walking-skeleton phase.
///
/// Keeps the scaffold branding and adds a minimal transport: a play/pause
/// button that reflects real playback state, and a seek bar with position /
/// duration labels. All state is read from Riverpod providers that wrap
/// `PlayerService` — the UI never touches the player or handler directly.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Viby'),
        actions: <Widget>[
          // Temporary entry points to the throwaway debug screens.
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug: library scan',
            onPressed: () => context.push(AppRoutes.debugScan),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_outlined),
            tooltip: 'Debug: queue',
            onPressed: () => context.push(AppRoutes.debugQueue),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.graphic_eq,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Viby', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text('Sample · Viby', style: text.bodyMedium),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _PlayerControls(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transport controls: seek bar + play/pause, driven entirely by providers.
class _PlayerControls extends ConsumerWidget {
  const _PlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final Duration duration =
        ref.watch(trackDurationProvider).valueOrNull ?? Duration.zero;

    final double maxMs =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final double valueMs =
        position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Column(
      children: <Widget>[
        Slider(
          value: valueMs,
          max: maxMs,
          onChanged: duration.inMilliseconds > 0
              ? (double v) => ref
                  .read(playerServiceProvider)
                  .seek(Duration(milliseconds: v.round()))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        IconButton(
          iconSize: 72,
          color: Theme.of(context).colorScheme.primary,
          icon: Icon(
            playing ? Icons.pause_circle : Icons.play_circle,
          ),
          onPressed: () {
            final service = ref.read(playerServiceProvider);
            if (playing) {
              service.pause();
            } else {
              service.play();
            }
          },
          tooltip: playing ? 'Pause' : 'Play',
        ),
      ],
    );
  }
}

/// Formats a duration as `m:ss` (or `h:mm:ss` past an hour) for the labels.
String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final int hours = d.inHours;
  final String minutes = hours > 0 ? two(d.inMinutes.remainder(60)) : '${d.inMinutes.remainder(60)}';
  final String seconds = two(d.inSeconds.remainder(60));
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
