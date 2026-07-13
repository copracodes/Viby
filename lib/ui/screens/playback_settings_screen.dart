import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/replay_gain.dart';
import '../../state/playback_providers.dart';
import '../theme/tokens.dart';

/// Settings › Playback › Volume normalization.
///
/// The whole screen exists to make one promise legible: Viby will level the
/// loudness *of files that say how loud they are*, and will not invent a level
/// for files that don't.
class PlaybackSettingsScreen extends ConsumerWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PlaybackSettings settings =
        ref.watch(playbackSettingsControllerProvider);
    final PlaybackSettingsController controller =
        ref.read(playbackSettingsControllerProvider.notifier);
    final ReplayGainSettings rg = settings.replayGain;
    final bool on = rg.mode != ReplayGainMode.off;

    return Scaffold(
      appBar: AppBar(title: const Text('Volume normalization')),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
            child: Text(
              'Evens out loudness between tracks using the ReplayGain tags in '
              'your files, so a quiet album and a loud one play at the same '
              'level.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          RadioGroup<ReplayGainMode>(
            groupValue: rg.mode,
            onChanged: (ReplayGainMode? m) {
              if (m != null) controller.setMode(m);
            },
            child: const Column(
              children: <Widget>[
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.off,
                  title: Text('Off'),
                  subtitle: Text('Play every file at its own level'),
                ),
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.album,
                  title: Text('Album'),
                  subtitle: Text(
                    'Level albums against each other, but keep the quiet and '
                    'loud moments within an album (falls back to track gain)',
                  ),
                ),
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.track,
                  title: Text('Track'),
                  subtitle: Text(
                    'Level every song independently — best on shuffle',
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            enabled: on,
            title: const Text('Pre-amp'),
            subtitle: Text(
              '${rg.preampDb >= 0 ? '+' : ''}${rg.preampDb.toStringAsFixed(1)} dB',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Slider(
              value: rg.preampDb.clamp(kPreampMinDb, kPreampMaxDb),
              min: kPreampMinDb,
              max: kPreampMaxDb,
              divisions: 24,
              label: '${rg.preampDb.toStringAsFixed(1)} dB',
              onChanged: on ? controller.setPreamp : null,
            ),
          ),
          SwitchListTile(
            value: rg.preventClipping,
            onChanged: on ? controller.setPreventClipping : null,
            title: const Text('Prevent clipping'),
            subtitle: const Text(
              'Hold the volume below the point where a hot master would '
              'distort, using the peak recorded in the file',
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              'Files with no ReplayGain tags play untouched. Viby never guesses '
              'a level for them — a made-up gain would make them jump against '
              'everything else. Tag them with a tool like loudgain or foobar2000 '
              'and they get levelled after the next scan.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
