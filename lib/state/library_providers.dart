import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/db/daos/library_dao.dart';
import '../data/sources/local/artwork_service.dart';
import '../data/sources/local/local_scanner.dart';
import '../data/sources/local/permission_service.dart';
import 'database_providers.dart';

part 'library_providers.g.dart';

// --- Services --------------------------------------------------------------

@Riverpod(keepAlive: true)
OnAudioQuery onAudioQuery(Ref ref) => OnAudioQuery();

@Riverpod(keepAlive: true)
AudioPermissionService audioPermissionService(Ref ref) =>
    AudioPermissionService(ref.watch(onAudioQueryProvider));

@Riverpod(keepAlive: true)
ArtworkService artworkService(Ref ref) =>
    ArtworkService(ref.watch(onAudioQueryProvider));

@Riverpod(keepAlive: true)
LocalScanner localScanner(Ref ref) => LocalScanner(
  audioQuery: ref.watch(onAudioQueryProvider),
  libraryDao: ref.watch(vibyDatabaseProvider).libraryDao,
  artworkService: ref.watch(artworkServiceProvider),
);

// --- Permission state ------------------------------------------------------

/// Current audio-permission status; any screen can gate on this.
@riverpod
class AudioPermission extends _$AudioPermission {
  @override
  Future<AudioPermissionStatus> build() {
    return ref.watch(audioPermissionServiceProvider).check();
  }

  Future<void> request() async {
    state = const AsyncValue<AudioPermissionStatus>.loading();
    state = await AsyncValue.guard(
      () => ref.read(audioPermissionServiceProvider).request(),
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(audioPermissionServiceProvider).check(),
    );
  }

  Future<void> openSettings() =>
      ref.read(audioPermissionServiceProvider).openSettings();
}

// --- Scan state ------------------------------------------------------------

/// Outcome counts of a finished scan.
class ScanSummary {
  const ScanSummary({
    required this.tracks,
    required this.deleted,
    required this.errors,
    required this.elapsed,
  });

  final int tracks;
  final int deleted;
  final int errors;
  final Duration elapsed;
}

sealed class LibraryScanState {
  const LibraryScanState();
}

class LibraryScanIdle extends LibraryScanState {
  const LibraryScanIdle();
}

class LibraryScanRunning extends LibraryScanState {
  const LibraryScanRunning(this.progress);
  final ScanProgress progress;
}

class LibraryScanDone extends LibraryScanState {
  const LibraryScanDone(this.summary);
  final ScanSummary summary;
}

class LibraryScanError extends LibraryScanState {
  const LibraryScanError(this.error);
  final Object error;
}

/// Drives and reflects the library scan: idle → scanning(progress) →
/// done(summary) | error.
@riverpod
class LibraryScan extends _$LibraryScan {
  StreamSubscription<ScanProgress>? _subscription;

  @override
  LibraryScanState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const LibraryScanIdle();
  }

  Future<void> fullScan() async {
    if (!await _ensurePermission()) return;
    _listen(ref.read(localScannerProvider).fullScan());
  }

  Future<void> incrementalRescan() async {
    if (!await _ensurePermission()) return;
    _listen(ref.read(localScannerProvider).incrementalRescan());
  }

  void cancel() => ref.read(localScannerProvider).cancel();

  /// Hard gate before touching on_audio_query: querying without the audio
  /// permission makes the plugin double-reply and crash the app natively, so we
  /// refuse to start a scan unless it's granted.
  Future<bool> _ensurePermission() async {
    final AudioPermissionStatus status =
        await ref.read(audioPermissionServiceProvider).check();
    if (status == AudioPermissionStatus.granted) return true;
    state = LibraryScanError(
      'Audio permission not granted (${status.name}). '
      'Grant it before scanning.',
    );
    return false;
  }

  /// Runs a full scan on first launch once permission is granted and the
  /// library is still empty.
  Future<void> autoScanIfNeeded() async {
    final AudioPermissionStatus permission =
        await ref.read(audioPermissionServiceProvider).check();
    if (permission != AudioPermissionStatus.granted) return;
    final int count = await ref.read(vibyDatabaseProvider).libraryDao.trackCount();
    if (count == 0) fullScan();
  }

  void _listen(Stream<ScanProgress> stream) {
    _subscription?.cancel();
    state = const LibraryScanRunning(
      ScanProgress(phase: ScanPhase.querying, found: 0, processed: 0),
    );
    _subscription = stream.listen(
      (ScanProgress progress) {
        state = progress.phase == ScanPhase.done
            ? LibraryScanDone(
                ScanSummary(
                  tracks: progress.processed,
                  deleted: progress.deleted,
                  errors: progress.errors,
                  elapsed: progress.elapsed,
                ),
              )
            : LibraryScanRunning(progress);
      },
      onError: (Object error, StackTrace stack) {
        state = LibraryScanError(error);
      },
    );
  }
}

// --- Library reads (debug UI) ---------------------------------------------

/// All tracks with resolved album/artist names (title order) — used by the
/// debug scan screen to prove the DB round-trip. An empty search matches every
/// track while still carrying the joined artist/album names.
@riverpod
Stream<List<TrackWithMeta>> allTracks(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.searchTracks('');
