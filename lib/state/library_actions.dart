import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/daos/library_dao.dart';
import '../data/db/viby_database.dart';
import '../data/models/track.dart';
import 'library_providers.dart';
import 'queue_provider.dart';
import 'track_resolver.dart';

/// Play helpers shared by the library screens: resolve DB rows into playable
/// [Track]s (artwork filled in) and drive the queue. Kept in one place so no
/// screen re-implements the resolve → setQueue dance.

/// Replaces the queue with [metas] and starts playing at [startIndex].
Future<void> playMetas(
  WidgetRef ref,
  List<TrackWithMeta> metas, {
  int startIndex = 0,
  bool shuffle = false,
}) async {
  if (metas.isEmpty) return;
  final List<Track> tracks =
      await resolveTracks(metas, ref.read(artworkServiceProvider));
  await ref.read(queueControllerProvider.notifier).setQueue(
        tracks,
        startIndex: startIndex,
        autoPlay: true,
        shuffle: shuffle,
      );
}

/// Same as [playMetas] but from bare [TrackRow]s, tagging them with the
/// album/artist names already known from the surrounding screen.
Future<void> playTrackRows(
  WidgetRef ref,
  List<TrackRow> rows, {
  int startIndex = 0,
  String? albumName,
  String? artistName,
  bool shuffle = false,
}) {
  return playMetas(
    ref,
    rows
        .map(
          (TrackRow r) => TrackWithMeta(
            track: r,
            albumName: albumName,
            artistName: artistName,
          ),
        )
        .toList(),
    startIndex: startIndex,
    shuffle: shuffle,
  );
}

Future<Track> _resolveOne(WidgetRef ref, TrackWithMeta meta) async {
  final List<Track> resolved =
      await resolveTracks(<TrackWithMeta>[meta], ref.read(artworkServiceProvider));
  return resolved.single;
}

/// Queues [meta] to play right after the current track.
Future<void> playNextMeta(WidgetRef ref, TrackWithMeta meta) async {
  final Track track = await _resolveOne(ref, meta);
  await ref.read(queueControllerProvider.notifier).playNext(track);
}

/// Appends [meta] to the end of the queue.
Future<void> addMetaToQueue(WidgetRef ref, TrackWithMeta meta) async {
  final Track track = await _resolveOne(ref, meta);
  await ref.read(queueControllerProvider.notifier).addTrack(track);
}
