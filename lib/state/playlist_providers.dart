import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/db/daos/playlist_dao.dart';
import 'database_providers.dart';

part 'playlist_providers.g.dart';

/// Every playlist with its track count + collage keys (newest-modified first).
@riverpod
Stream<List<PlaylistSummary>> playlistSummaries(Ref ref) =>
    ref.watch(vibyDatabaseProvider).playlistDao.watchPlaylistSummaries();

/// A playlist with its tracks (+ names) in position order — playlist detail.
@riverpod
Stream<PlaylistWithMeta?> playlistDetail(Ref ref, String playlistId) =>
    ref.watch(vibyDatabaseProvider).playlistDao.watchPlaylistWithMeta(playlistId);

/// The set of playlist ids currently containing [trackId] — the add-to-playlist
/// sheet's checkmarks.
@riverpod
Stream<Set<String>> playlistIdsContaining(Ref ref, String trackId) =>
    ref.watch(vibyDatabaseProvider).playlistDao.watchPlaylistIdsContaining(trackId);

/// Recent successful searches (newest first) — the empty-field chips.
@riverpod
Stream<List<String>> recentSearches(Ref ref) =>
    ref.watch(vibyDatabaseProvider).searchDao.watchRecentSearches();
