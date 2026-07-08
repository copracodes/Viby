import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/pro.dart';
import '../../core/router.dart';
import '../../data/sources/local/permission_service.dart';
import '../../state/haptics_providers.dart';
import '../../state/library_providers.dart';
import '../../state/theme_providers.dart';
import '../theme/theme_collection.dart';
import '../theme/tokens.dart';
import '../theme/viby_theme.dart';
import '../widgets/theme_preview_card.dart';

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
          const _SectionHeader('Audio'),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Equalizer'),
            subtitle: const Text('Tune the sound · presets · loudness'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.eq),
          ),
          const Divider(),
          const _SectionHeader('Appearance'),
          const _AppearanceSection(),
          const Divider(),
          const _SectionHeader('Feedback'),
          const _HapticsTile(),
          const Divider(),
          const _SectionHeader('About'),
          const _AboutSection(),
          // Developer tools ship in non-release builds only (debug + profile,
          // so the profile perf pass can seed 10k) — stripped from release.
          if (!kReleaseMode) ...<Widget>[
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
          ],
          const SizedBox(height: Spacing.xl),
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

/// Appearance: the theme gallery (live preview cards) + system-follow, AMOLED
/// override and dynamic-colour toggles.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
    final ThemeSettings controller = ref.read(themeSettingsProvider.notifier);

    // The active theme (drives which toggles are enabled).
    final VibyTheme active = resolveActiveTheme(
      selectedId: settings.themeId,
      systemFollow: settings.systemFollow,
      platformBrightness: MediaQuery.platformBrightnessOf(context),
      amoledOverride: settings.amoledOverride,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
          child: Text('Theme'),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
            itemCount: kThemeCollection.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (BuildContext context, int i) {
              final VibyTheme t = kThemeCollection[i];
              final bool selected =
                  !settings.systemFollow && settings.themeId == t.id;
              return ThemePreviewCard(
                theme: t,
                selected: selected,
                onTap: () {
                  if (!kProThemesUnlocked && t.isPro) return; // TODO(3.4): paywall
                  controller.selectTheme(t.id);
                },
              );
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.brightness_auto_outlined),
          title: const Text('Follow system light/dark'),
          subtitle: const Text('Use Classic Light or Dark to match your device'),
          value: settings.systemFollow,
          onChanged: controller.setSystemFollow,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: const Text('AMOLED black'),
          subtitle: Text(
            active.isDark
                ? 'Pure-black surfaces on dark themes'
                : 'Only affects dark themes',
          ),
          value: settings.amoledOverride,
          onChanged: active.isDark ? controller.setAmoledOverride : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('Dynamic color from artwork'),
          subtitle: Text(
            active.acceptsDynamicSeed
                ? 'Now Playing tints to the current album art'
                : '${active.name} keeps its own colours',
          ),
          value: settings.dynamicColor,
          onChanged:
              active.acceptsDynamicSeed ? controller.setDynamicColor : null,
        ),
      ],
    );
  }
}

/// About: version/build, themed licenses, and a credits line.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Viby'),
          subtitle: Text(
            _version.isEmpty ? 'A premium music player' : 'Version $_version',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Viby',
            applicationVersion: _version,
            applicationLegalese: '© 2026 Copra',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.xs, Spacing.lg, Spacing.sm),
          child: Text(
            'Made with care for people who love their music.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Toggles subtle system haptics (persisted). See [HapticsService].
class _HapticsTile extends ConsumerWidget {
  const _HapticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled = ref.watch(hapticsEnabledProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.vibration_outlined),
      title: const Text('Haptic feedback'),
      subtitle: const Text('Subtle taps on play, skip and reorder'),
      value: enabled,
      onChanged: (bool on) {
        if (on) ref.read(hapticsServiceProvider).selection();
        ref.read(hapticsEnabledProvider.notifier).setEnabled(on);
      },
    );
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
