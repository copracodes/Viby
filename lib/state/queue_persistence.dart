import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/player_service.dart';
import '../data/db/daos/library_dao.dart';
import '../data/db/daos/queue_dao.dart';
import '../data/models/track.dart';
import '../data/sources/local/artwork_service.dart';
import 'database_providers.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'queue_provider.dart';
import 'track_resolver.dart';

part 'queue_persistence.g.dart';

/// Persists the queue to `QueueDao` and restores it on cold start.
///
/// Saves are debounced (2s) on any queue/order/mode change and, while playing,
/// the position is checkpointed every 10s and on pause. Restore rebuilds the
/// queue WITHOUT autoplay, dropping ids whose tracks were deleted since last
/// session and clamping the saved index onto the survivors.
@Riverpod(keepAlive: true)
QueuePersistence queuePersistence(Ref ref) {
  final controller = QueuePersistence(
    queueDao: ref.watch(vibyDatabaseProvider).queueDao,
    libraryDao: ref.watch(vibyDatabaseProvider).libraryDao,
    artwork: ref.watch(artworkServiceProvider),
    player: ref.watch(playerServiceProvider),
    readQueue: () => ref.read(queueControllerProvider),
    notifier: () => ref.read(queueControllerProvider.notifier),
  );
  ref.onDispose(controller.dispose);
  // Debounced save whenever the queue's structure / order / modes change.
  ref.listen<QueueState>(
    queueControllerProvider,
    (_, __) => controller.onQueueChanged(),
  );
  return controller;
}

class QueuePersistence {
  QueuePersistence({
    required this.queueDao,
    required this.libraryDao,
    required this.artwork,
    required this.player,
    required this.readQueue,
    required this.notifier,
  });

  final QueueDao queueDao;
  final LibraryDao libraryDao;
  final ArtworkService artwork;
  final PlayerService player;
  final QueueState Function() readQueue;
  final QueueController Function() notifier;

  static const Duration _debounce = Duration(seconds: 2);
  static const Duration _positionInterval = Duration(seconds: 10);

  Timer? _debounceTimer;
  Timer? _positionTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  Duration _lastPosition = Duration.zero;
  bool _playing = false;
  bool _started = false;

  /// Begins tracking playback for position checkpoints. Called after restore so
  /// the restore's own load doesn't race with the first save.
  void start() {
    if (_started) return;
    _started = true;
    _posSub = player.position.listen((Duration p) => _lastPosition = p);
    _playingSub = player.playing.listen((bool playing) {
      _playing = playing;
      if (!playing) unawaited(_save()); // checkpoint on pause
    });
    _positionTimer = Timer.periodic(_positionInterval, (_) {
      if (_playing) unawaited(_save());
    });
  }

  void onQueueChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(_save()));
  }

  Future<void> _save() async {
    final QueueState q = readQueue();
    if (q.isEmpty) return;
    await queueDao.saveQueueState(
      QueueSnapshot(
        trackIds: q.tracks.map((Track t) => t.id).toList(),
        currentIndex: q.currentIndex < 0 ? 0 : q.currentIndex,
        positionMs: _lastPosition.inMilliseconds,
        shuffleOn: q.shuffleOn,
        repeatMode: q.repeatMode,
      ),
    );
  }

  /// Cold-start restore. Safe to call once at app launch.
  Future<void> restore() async {
    final QueueSnapshot? snap = await queueDao.loadQueueState();
    if (snap == null || snap.trackIds.isEmpty) {
      start();
      return;
    }
    final List<TrackWithMeta> metas =
        await libraryDao.getTracksByIds(snap.trackIds);
    final List<Track> resolved = await resolveTracks(metas, artwork);
    final Map<String, Track> byId = <String, Track>{
      for (final Track t in resolved) t.id: t,
    };
    final RestoredQueue restored = buildRestoredQueue(
      trackIds: snap.trackIds,
      savedIndex: snap.currentIndex,
      byId: byId,
    );
    if (restored.tracks.isNotEmpty) {
      _lastPosition = Duration(milliseconds: snap.positionMs);
      await notifier().restore(
        restored.tracks,
        currentIndex: restored.currentIndex,
        shuffleOn: snap.shuffleOn,
        repeatMode: snap.repeatMode,
        position: Duration(milliseconds: snap.positionMs),
      );
    }
    start();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _positionTimer?.cancel();
    _posSub?.cancel();
    _playingSub?.cancel();
  }
}
