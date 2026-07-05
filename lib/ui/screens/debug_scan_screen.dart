import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/daos/library_dao.dart';
import '../../data/sources/local/local_scanner.dart';
import '../../data/sources/local/permission_service.dart';
import '../../state/library_providers.dart';

/// THROWAWAY debug screen (route `/debug-scan`) for driving the local scanner
/// and proving the DB round-trip. No polish; deleted once real library UI lands.
class DebugScanScreen extends ConsumerWidget {
  const DebugScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AudioPermissionStatus> permission =
        ref.watch(audioPermissionProvider);
    final LibraryScanState scan = ref.watch(libraryScanProvider);
    final AsyncValue<List<TrackWithMeta>> tracks = ref.watch(allTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug · Library Scan'),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const _Banner(),
          const SizedBox(height: 12),
          _PermissionSection(permission: permission),
          const Divider(height: 32),
          _ScanSection(scan: scan),
          const Divider(height: 32),
          _TrackList(tracks: tracks),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        '⚠ Throwaway debug tooling — not shipped UI.',
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _PermissionSection extends ConsumerWidget {
  const _PermissionSection({required this.permission});

  final AsyncValue<AudioPermissionStatus> permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AudioPermission controller = ref.read(audioPermissionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Permission', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        permission.when(
          loading: () => const Text('Checking…'),
          error: (Object e, _) => Text('Error: $e'),
          data: (AudioPermissionStatus status) => Text('Status: ${status.name}'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton(
              onPressed: controller.request,
              child: const Text('Request permission'),
            ),
            OutlinedButton(
              onPressed: controller.openSettings,
              child: const Text('Open app settings'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScanSection extends ConsumerWidget {
  const _ScanSection({required this.scan});

  final LibraryScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryScan controller = ref.read(libraryScanProvider.notifier);
    final bool scanning = scan is LibraryScanRunning;
    // Scanning without the audio permission crashes the on_audio_query plugin
    // natively, so the scan buttons stay disabled until it's granted.
    final bool granted = ref.watch(audioPermissionProvider).valueOrNull ==
        AudioPermissionStatus.granted;
    final bool canStart = granted && !scanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Scan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!granted)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Grant audio permission above to enable scanning.'),
          ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton(
              onPressed: canStart ? controller.fullScan : null,
              child: const Text('Full scan'),
            ),
            FilledButton.tonal(
              onPressed: canStart ? controller.incrementalRescan : null,
              child: const Text('Incremental rescan'),
            ),
            OutlinedButton(
              onPressed: scanning ? controller.cancel : null,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ScanStatus(scan: scan),
      ],
    );
  }
}

class _ScanStatus extends StatelessWidget {
  const _ScanStatus({required this.scan});

  final LibraryScanState scan;

  @override
  Widget build(BuildContext context) {
    switch (scan) {
      case LibraryScanIdle():
        return const Text('Idle.');
      case LibraryScanRunning(:final ScanProgress progress):
        final double? value = progress.found > 0
            ? (progress.processed / progress.found).clamp(0.0, 1.0)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(value: value),
            const SizedBox(height: 8),
            Text(
              '${progress.phase.name} · '
              '${progress.processed}/${progress.found}'
              '${progress.errors > 0 ? ' · ${progress.errors} art errors' : ''}',
            ),
          ],
        );
      case LibraryScanDone(:final ScanSummary summary):
        return Text(
          'Done: ${summary.tracks} tracks, ${summary.deleted} deleted, '
          '${summary.errors} art errors in '
          '${summary.elapsed.inMilliseconds}ms.',
        );
      case LibraryScanError(:final Object error):
        return Text('Error: $error');
    }
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks});

  final AsyncValue<List<TrackWithMeta>> tracks;

  @override
  Widget build(BuildContext context) {
    return tracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Text('Error: $e'),
      data: (List<TrackWithMeta> all) {
        final List<TrackWithMeta> first = all.take(100).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Tracks in DB: ${all.length} (showing ${first.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...first.map(
              (TrackWithMeta t) => ListTile(
                dense: true,
                title: Text(t.track.title, maxLines: 1),
                subtitle: Text(
                  '${t.artistName ?? '—'} · ${_formatMs(t.track.durationMs)}',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatMs(int ms) {
  final Duration d = Duration(milliseconds: ms);
  final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}
