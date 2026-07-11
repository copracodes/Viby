import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lyrics_providers.dart';
import '../theme/tokens.dart';

/// Explains how to add offline lyrics: a `.lrc` sidecar next to the song, an
/// embedded lyrics tag, or the SAF folder grant needed to read standalone `.lrc`
/// files. v1 is offline-pure — no online lyrics search (a v2 ledger item).
Future<void> showHowToAddLyricsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const _HowToSheet(),
  );
}

class _HowToSheet extends ConsumerWidget {
  const _HowToSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool granted = ref.watch(lyricsFolderProvider) != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.xl, 0, Spacing.xl, Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Add lyrics', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.lg),
            const _Step(
              icon: Icons.description_outlined,
              title: 'Add a .lrc file',
              body: 'Put a lyrics file with the same name next to the song — '
                  'e.g. "Song.lrc" beside "Song.mp3". Timestamped '
                  '[mm:ss.xx] lines scroll and highlight; plain text shows '
                  'as static lyrics.',
            ),
            const _Step(
              icon: Icons.audiotrack_outlined,
              title: 'Or embed lyrics in the file',
              body: 'Lyrics saved inside the song’s tags (USLT/SYLT) are '
                  'picked up automatically — no folder access needed.',
            ),
            const _Step(
              icon: Icons.folder_open_outlined,
              title: 'Grant a folder for .lrc files',
              body: 'Android blocks reading standalone .lrc files without a '
                  'one-time folder grant. Point Viby at your music folder and '
                  '.lrc files (and a /Lyrics/ subfolder) start working.',
            ),
            const SizedBox(height: Spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final bool ok = await ref
                      .read(lyricsFolderProvider.notifier)
                      .grantFolder();
                  if (ok && context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(granted ? 'Change lyrics folder' : 'Grant folder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
