import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_names.dart';
import '../../data/db/viby_database.dart';
import '../../data/sources/local/permission_service.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../home/home_logic.dart';
import '../player/pressable_scale.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

/// Home: a time-of-day greeting over recently played / added / top-tracks
/// strips, or a welcoming scan call-to-action when the library is empty.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> count = ref.watch(libraryTrackCountProvider);
    return Scaffold(
      body: count.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (int tracks) =>
            tracks == 0 ? const _EmptyLibrary() : const _HomeContent(),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int topCount =
        ref.watch(topTracksProvider).valueOrNull?.length ?? 0;

    return CustomScrollView(
      slivers: <Widget>[
        const SliverToBoxAdapter(child: _Greeting()),
        const SliverToBoxAdapter(
          child: _Section(title: 'Recently played', kind: _SectionKind.played),
        ),
        if (shouldShowTopTracks(topCount))
          const SliverToBoxAdapter(
            child: _Section(title: 'Your top tracks', kind: _SectionKind.top),
          ),
        const SliverToBoxAdapter(
          child: _Section(title: 'Recently added', kind: _SectionKind.added),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        MediaQuery.paddingOf(context).top + Spacing.lg,
        Spacing.lg,
        Spacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            greetingForHour(DateTime.now().hour),
            style: theme.textTheme.headlineMedium,
          ),
          Text(
            'Viby',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

enum _SectionKind { played, added, top }

class _Section extends ConsumerWidget {
  const _Section({required this.title, required this.kind});

  final String title;
  final _SectionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TrackRow>> rows = switch (kind) {
      _SectionKind.played => ref.watch(recentlyPlayedProvider),
      _SectionKind.added => ref.watch(recentlyAddedProvider),
      _SectionKind.top => ref.watch(topTracksProvider),
    };
    final List<TrackRow> data = rows.valueOrNull ?? const <TrackRow>[];
    if (data.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.md, Spacing.sm, Spacing.xs),
          child: Row(
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              TextButton(
                // Full-list routes are stubbed for the beauty pass; jump to the
                // Library for now.
                onPressed: () => context.go('/library'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            itemCount: data.length,
            itemBuilder: (BuildContext context, int i) => _TrackCard(
              row: data[i],
              onTap: () => playTrackRows(ref, <TrackRow>[data[i]]),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends ConsumerWidget {
  const _TrackCard({required this.row, required this.onTap});

  final TrackRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? artist =
        ref.watch(artistProvider(row.artistId)).valueOrNull?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.97,
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AlbumArt(
                artworkKey: row.artworkKey,
                size: 150,
                borderRadius: Radii.md,
                outline: true,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                artist.artistOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    final ThemeData theme = Theme.of(context);
    final bool scanning = ref.watch(libraryScanProvider) is LibraryScanRunning;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_music_outlined,
                size: 44,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Welcome to Viby', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.sm),
            Text(
              'Scan your device to bring your music in.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xl),
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
