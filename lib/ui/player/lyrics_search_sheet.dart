import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/lyrics/query_cleanup.dart';
import '../../data/lyrics/sources/lrclib_source.dart';
import '../../data/models/track.dart';
import '../../state/lyrics_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/tokens.dart';

/// The manual "Search online" escape hatch: an editable query (prefilled with
/// the *cleaned* title/artist) and a results list showing duration so the user
/// can pick the right take when auto-match got it wrong. Tapping a result caches
/// it for the current track.
Future<void> showLyricsSearchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  late final TextEditingController _track;
  late final TextEditingController _artist;
  List<LrclibRecord>? _results;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final Track? track = ref.read(queueControllerProvider).currentTrack;
    final LyricsQuery q = cleanLyricsQuery(
      title: track?.title ?? '',
      artist: track?.artistName ?? '',
      album: track?.albumName,
    );
    _track = TextEditingController(text: q.track);
    _artist = TextEditingController(text: q.artist);
  }

  @override
  void dispose() {
    _track.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final List<LrclibRecord> results = await ref
        .read(lyricsControllerProvider.notifier)
        .searchOnline(track: _track.text, artist: _artist.text);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _apply(LrclibRecord record) async {
    await ref.read(lyricsControllerProvider.notifier).applyOnlineResult(record);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.xl,
        right: Spacing.xl,
        bottom: Spacing.xl + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Search lyrics online', style: theme.textTheme.titleLarge),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _track,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _artist,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              labelText: 'Artist',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Flexible(child: _resultsView()),
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(Spacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final List<LrclibRecord>? results = _results;
    if (results == null) return const SizedBox.shrink();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Text(
          'No matches found. Try adjusting the title or artist.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (BuildContext context, int i) {
        final LrclibRecord r = results[i];
        final bool synced =
            r.syncedLyrics != null && r.syncedLyrics!.trim().isNotEmpty;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(r.trackName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            r.artistName.artistOrUnknown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Icon(
            r.instrumental
                ? Icons.music_note
                : (synced ? Icons.lyrics : Icons.notes),
          ),
          trailing: Text(_fmt(r.durationSec)),
          onTap: () => _apply(r),
        );
      },
    );
  }

  static String _fmt(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
