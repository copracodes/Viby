import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/daos/library_dao.dart';
import '../../state/database_providers.dart';
import '../../state/library_actions.dart';
import '../../state/library_providers.dart';
import '../../state/playlist_providers.dart';
import '../widgets/track_tile.dart';

/// Search: a debounced (300ms, in the provider) query over titles, albums and
/// artists. Results are tracks; tapping one plays the result set from there and
/// records the query. With the field empty, recent searches show as chips.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() => _query = value);
  }

  void _onResultTapped(List<TrackWithMeta> tracks, int index) {
    // A tapped result marks the query as "successful" — worth remembering.
    ref.read(vibyDatabaseProvider).searchDao.recordSearch(_query);
    playMetas(ref, tracks, startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<TrackWithMeta>> results =
        ref.watch(trackSearchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search songs, albums, artists',
            border: InputBorder.none,
          ),
          onChanged: (String v) => setState(() => _query = v),
        ),
        actions: <Widget>[
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => _setQuery(''),
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? _RecentSearches(onSelected: _setQuery)
          : results.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (List<TrackWithMeta> tracks) => tracks.isEmpty
                  ? const Center(child: Text('No matches.'))
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (BuildContext context, int i) => TrackTile(
                        meta: tracks[i],
                        onTap: () => _onResultTapped(tracks, i),
                      ),
                    ),
            ),
    );
  }
}

/// Recent-search chips shown when the field is empty, with a clear-all action.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> recents =
        ref.watch(recentSearchesProvider).valueOrNull ?? const <String>[];
    if (recents.isEmpty) {
      return const Center(child: Text('Search your library.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Recent', style: Theme.of(context).textTheme.titleSmall),
              TextButton(
                onPressed: () =>
                    ref.read(vibyDatabaseProvider).searchDao.clearSearches(),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String term in recents)
                ActionChip(
                  avatar: const Icon(Icons.history, size: 18),
                  label: Text(term),
                  onPressed: () => onSelected(term),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
