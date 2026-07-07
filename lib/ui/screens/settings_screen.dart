import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/sources/local/permission_service.dart';
import '../../state/library_providers.dart';

/// Settings: rescan (with progress), a theme stub, the Developer section
/// (throwaway debug tools) and an About placeholder.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _rescan(WidgetRef ref) async {
    await ref.read(audioPermissionProvider.notifier).request();
    final bool granted = ref.read(audioPermissionProvider).valueOrNull ==
        AudioPermissionStatus.granted;
    if (granted) await ref.read(libraryScanProvider.notifier).incrementalRescan();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryScanState scan = ref.watch(libraryScanProvider);
    final bool scanning = scan is LibraryScanRunning;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('Library'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Rescan library'),
            subtitle: Text(_scanSubtitle(scan)),
            trailing: scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: scanning ? null : () => _rescan(ref),
          ),
          if (scan is LibraryScanRunning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: scan.progress.found > 0
                    ? (scan.progress.processed / scan.progress.found)
                        .clamp(0.0, 1.0)
                    : null,
              ),
            ),
          const Divider(),
          const _SectionHeader('Appearance'),
          const ListTile(
            leading: Icon(Icons.brightness_6_outlined),
            title: Text('Theme'),
            subtitle: Text('Follows system (theme options coming soon)'),
            enabled: false,
          ),
          const Divider(),
          const _SectionHeader('Developer'),
          const _SeederTile(),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Library scan (debug)'),
            onTap: () => context.push(AppRoutes.debugScan),
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: const Text('Queue (debug)'),
            onTap: () => context.push(AppRoutes.debugQueue),
          ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Viby'),
            subtitle: Text('A premium music player.'),
          ),
        ],
      ),
    );
  }

  String _scanSubtitle(LibraryScanState scan) {
    return switch (scan) {
      LibraryScanIdle() => 'Look for new and changed music',
      LibraryScanRunning(:final progress) =>
        '${progress.phase.name} · ${progress.processed}/${progress.found}',
      LibraryScanDone(:final summary) =>
        'Done: ${summary.tracks} tracks, ${summary.deleted} removed'
            '${summary.repaired > 0 ? ', ${summary.repaired} tags repaired' : ''}',
      LibraryScanError(:final error) => 'Error: $error',
    };
  }
}

/// Debug-only: seed / clear a synthetic 10k-track library for scale testing.
class _SeederTile extends ConsumerWidget {
  const _SeederTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SeedState seed = ref.watch(seederControllerProvider);
    final SeederController controller =
        ref.read(seederControllerProvider.notifier);
    final bool running = seed is SeedRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Synthetic library (debug)'),
          subtitle: Text(_seedSubtitle(seed)),
          trailing: running
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: running ? null : controller.seed,
                child: const Text('Seed 10k'),
              ),
              OutlinedButton(
                onPressed: running ? null : controller.clear,
                child: const Text('Clear synthetic'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _seedSubtitle(SeedState seed) {
    return switch (seed) {
      SeedIdle() => 'Insert 10k synthetic tracks straight into the DB',
      SeedRunning(:final written, :final total) =>
        total > 0 ? 'Seeding… $written/$total' : 'Clearing…',
      SeedDone(:final message) => message,
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
