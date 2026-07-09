import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_names.dart';
import '../../data/db/viby_database.dart';
import '../../data/sources/local/local_scanner.dart';
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
    // A slim progress hint while a scan runs with content already showing
    // (e.g. an incremental rescan, or the tail of the first scan after the
    // first chunk has populated the strips).
    final bool scanning = ref.watch(libraryScanProvider) is LibraryScanRunning;

    return Column(
      children: <Widget>[
        SizedBox(
          height: 2,
          child: scanning ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(child: _content(topCount)),
      ],
    );
  }

  Widget _content(int topCount) {
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

/// First-run empty state. There is deliberately **no manual scan button**: once
/// audio permission is granted the first scan starts automatically and this view
/// becomes a friendly progress state ("Setting up your library — N songs
/// found…"). Content appears progressively (the scanner commits in chunks), so
/// as soon as the first tracks land the Home screen swaps to [_HomeContent].
class _EmptyLibrary extends ConsumerStatefulWidget {
  const _EmptyLibrary();

  @override
  ConsumerState<_EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends ConsumerState<_EmptyLibrary> {
  bool _autoTriggered = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AudioPermissionStatus> permission =
        ref.watch(audioPermissionProvider);
    final LibraryScanState scan = ref.watch(libraryScanProvider);
    final bool granted =
        permission.valueOrNull == AudioPermissionStatus.granted;

    // The moment permission is granted, kick off the first scan automatically —
    // once (the guard survives rebuilds; a re-scan is impossible mid-scan).
    if (granted && !_autoTriggered && scan is! LibraryScanRunning) {
      _autoTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(libraryScanProvider.notifier).autoScanIfNeeded();
      });
    }

    if (scan is LibraryScanRunning) {
      return _Setup(progress: scan.progress);
    }
    if (!granted) {
      return _PermissionCta(
        denied: permission.valueOrNull == AudioPermissionStatus.permanentlyDenied,
        onGrant: () => ref.read(audioPermissionProvider.notifier).request(),
        onOpenSettings: () =>
            ref.read(audioPermissionProvider.notifier).openSettings(),
      );
    }
    // Granted + not running: either a scan finished with no music, or we're in
    // the brief gap before it starts.
    return _Message(
      icon: scan is LibraryScanDone
          ? Icons.music_off_outlined
          : Icons.library_music_outlined,
      title: scan is LibraryScanDone ? 'No music found' : 'Preparing…',
      body: scan is LibraryScanDone
          ? 'We couldn\'t find any audio on this device.'
          : 'Setting things up.',
    );
  }
}

/// The friendly first-run scan progress.
class _Setup extends StatelessWidget {
  const _Setup({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int found = progress.processed > 0 ? progress.processed : progress.found;
    final String detail = switch (progress.phase) {
      ScanPhase.querying => 'Scanning your device…',
      ScanPhase.writing =>
        found > 0 ? '$found songs found…' : 'Bringing your music in…',
      ScanPhase.artwork => 'Fetching album art…',
      ScanPhase.repair => 'Tidying up tags…',
      ScanPhase.done => 'Almost there…',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Setting up your library', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for audio access (first run, before any scan). Not a scan button — the
/// scan starts automatically once access is granted.
class _PermissionCta extends StatelessWidget {
  const _PermissionCta({
    required this.denied,
    required this.onGrant,
    required this.onOpenSettings,
  });

  final bool denied;
  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
              denied
                  ? 'Allow access to your music in Settings to build your library.'
                  : 'Allow access to your music and your library builds itself.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xl),
            FilledButton.icon(
              onPressed: denied ? onOpenSettings : onGrant,
              icon: Icon(denied ? Icons.settings : Icons.lock_open),
              label: Text(denied ? 'Open Settings' : 'Allow access'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple centered icon + title + body message.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.lg),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
