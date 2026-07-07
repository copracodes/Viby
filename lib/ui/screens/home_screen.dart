import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/viby_database.dart';
import '../../data/sources/local/permission_service.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../widgets/album_art.dart';

/// Home: recently played and recently added, or a scan call-to-action when the
/// library is empty.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> count = ref.watch(libraryTrackCountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Viby')),
      body: count.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (int tracks) =>
            tracks == 0 ? const _EmptyLibrary() : const _HomeContent(),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: const <Widget>[
        _Section(title: 'Recently played', kind: _SectionKind.played),
        _Section(title: 'Recently added', kind: _SectionKind.added),
      ],
    );
  }
}

enum _SectionKind { played, added }

class _Section extends ConsumerWidget {
  const _Section({required this.title, required this.kind});

  final String title;
  final _SectionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TrackRow>> rows = switch (kind) {
      _SectionKind.played => ref.watch(recentlyPlayedProvider),
      _SectionKind.added => ref.watch(recentlyAddedProvider),
    };
    final List<TrackRow> data = rows.valueOrNull ?? const <TrackRow>[];
    if (data.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: data.length,
            itemBuilder: (BuildContext context, int i) =>
                _TrackCard(row: data[i]),
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends ConsumerWidget {
  const _TrackCard({required this.row});

  final TrackRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 140,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => playTrackRows(ref, <TrackRow>[row]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AlbumArt(artworkKey: row.artworkKey, size: 132, borderRadius: 10),
              const SizedBox(height: 6),
              Text(
                row.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends ConsumerWidget {
  const _EmptyLibrary();

  Future<void> _scan(WidgetRef ref) async {
    await ref.read(audioPermissionProvider.notifier).request();
    final bool granted = ref.read(audioPermissionProvider).valueOrNull ==
        AudioPermissionStatus.granted;
    if (granted) await ref.read(libraryScanProvider.notifier).fullScan();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool scanning = ref.watch(libraryScanProvider) is LibraryScanRunning;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.library_music_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Your library is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan your device to find music.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: scanning ? null : () => _scan(ref),
              icon: scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(scanning ? 'Scanning…' : 'Scan library'),
            ),
          ],
        ),
      ),
    );
  }
}
