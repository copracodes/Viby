import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/db/daos/library_dao.dart';
import '../data/db/viby_database.dart';
import '../data/sources/local/artwork_service.dart';
import '../data/sources/local/library_maintenance.dart';
import '../data/sources/local/library_seeder.dart';
import '../data/sources/local/local_scanner.dart';
import '../data/sources/local/media_delete_channel.dart';
import '../data/sources/local/permission_service.dart';
import '../data/sources/local/tag_repair_service.dart';
import 'database_providers.dart';
import 'scan_triggers.dart';

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
TagRepairService tagRepairService(Ref ref) => TagRepairService(
  ref.watch(vibyDatabaseProvider).libraryDao,
  tagReader: const FileId3TagReader(),
);

/// The shared purge path (deleted files + tracks gone from MediaStore).
@Riverpod(keepAlive: true)
LibraryMaintenance libraryMaintenance(Ref ref) => LibraryMaintenance(
  ref.watch(vibyDatabaseProvider),
  artwork: ref.watch(artworkServiceProvider),
);

/// Permanent file deletion. A no-op implementation off Android, so the UI can
/// simply check `capable` (CLAUDE.md rule 6).
@Riverpod(keepAlive: true)
MediaDeleter mediaDeleter(Ref ref) => buildMediaDeleter();

@Riverpod(keepAlive: true)
LocalScanner localScanner(Ref ref) => LocalScanner(
  audioQuery: ref.watch(onAudioQueryProvider),
  libraryDao: ref.watch(vibyDatabaseProvider).libraryDao,
  artworkService: ref.watch(artworkServiceProvider),
  maintenance: ref.watch(libraryMaintenanceProvider),
  tagRepair: ref.watch(tagRepairServiceProvider),
  lyricsDao: ref.watch(vibyDatabaseProvider).lyricsDao,
);

/// Debug-only synthetic-library seeder (Settings › Developer).
@Riverpod(keepAlive: true)
LibrarySeeder librarySeeder(Ref ref) =>
    LibrarySeeder(ref.watch(vibyDatabaseProvider).libraryDao);

/// Progress/outcome of the debug seeder (Settings › Developer).
sealed class SeedState {
  const SeedState();
}

class SeedIdle extends SeedState {
  const SeedIdle();
}

class SeedRunning extends SeedState {
  const SeedRunning(this.written, this.total);
  final int written;
  final int total;
}

class SeedDone extends SeedState {
  const SeedDone(this.message);
  final String message;
}

/// Drives the debug seeder and reflects its progress. keepAlive so a long seed
/// isn't interrupted by the Settings screen rebuilding.
@Riverpod(keepAlive: true)
class SeederController extends _$SeederController {
  @override
  SeedState build() => const SeedIdle();

  Future<void> seed() async {
    if (state is SeedRunning) return;
    state = const SeedRunning(0, 10000);
    final Stopwatch sw = Stopwatch()..start();
    await ref.read(librarySeederProvider).seed(
          onProgress: (int written, int total) =>
              state = SeedRunning(written, total),
        );
    sw.stop();
    state = SeedDone('Seeded 10,000 tracks in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> clear() async {
    if (state is SeedRunning) return;
    state = const SeedRunning(0, 0);
    final int removed = await ref.read(librarySeederProvider).clear();
    state = SeedDone('Cleared $removed synthetic tracks');
  }
}

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
    required this.repaired,
    required this.elapsed,
    this.added = 0,
  });

  final int tracks;
  final int deleted;
  final int errors;
  final int repaired;
  final Duration elapsed;

  /// Newly-added tracks (incremental scans only) — drives the auto-detect
  /// "N songs added" snackbar.
  final int added;
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
///
/// keepAlive so an in-flight scan's progress survives the Settings screen being
/// torn down / rebuilt (e.g. on rotation) — the scan itself lives in the
/// keepAlive [LocalScanner], and a duplicate is impossible (its `_scanning`
/// guard rejects a second start).
@Riverpod(keepAlive: true)
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

  /// Preference key holding the epoch-millis of the last completed scan.
  static const String _lastScanAtKey = 'last_scan_at';

  /// Runs a full scan on first launch once permission is granted and the
  /// library is still empty.
  Future<void> autoScanIfNeeded() async {
    final AudioPermissionStatus permission =
        await ref.read(audioPermissionServiceProvider).check();
    if (permission != AudioPermissionStatus.granted) return;
    final int count = await ref.read(vibyDatabaseProvider).libraryDao.trackCount();
    if (count == 0) fullScan();
  }

  /// Runs an incremental rescan on app-resume, but only if enough time has
  /// passed since the last scan (see [shouldResumeScan]) — cheap and idempotent,
  /// so new music added while the app was backgrounded shows up without the user
  /// touching anything. A no-op without permission or while a scan is running.
  Future<void> maybeResumeScan() async {
    if (ref.read(localScannerProvider).isScanning) return;
    final AudioPermissionStatus permission =
        await ref.read(audioPermissionServiceProvider).check();
    if (permission != AudioPermissionStatus.granted) return;
    final String? raw =
        await ref.read(vibyDatabaseProvider).preferencesDao.get(_lastScanAtKey);
    final DateTime? lastScan = raw == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.tryParse(raw) ?? 0);
    if (shouldResumeScan(lastScan, DateTime.now())) {
      await incrementalRescan();
    }
  }

  Future<void> _recordScanTime() => ref
      .read(vibyDatabaseProvider)
      .preferencesDao
      .set(_lastScanAtKey, DateTime.now().millisecondsSinceEpoch.toString());

  void _listen(Stream<ScanProgress> stream) {
    _subscription?.cancel();
    state = const LibraryScanRunning(
      ScanProgress(phase: ScanPhase.querying, found: 0, processed: 0),
    );
    _subscription = stream.listen(
      (ScanProgress progress) {
        if (progress.phase == ScanPhase.done) {
          unawaited(_recordScanTime());
          state = LibraryScanDone(
            ScanSummary(
              tracks: progress.processed,
              deleted: progress.deleted,
              errors: progress.errors,
              repaired: progress.repaired,
              elapsed: progress.elapsed,
              added: progress.added,
            ),
          );
        } else {
          state = LibraryScanRunning(progress);
        }
      },
      onError: (Object error, StackTrace stack) {
        state = LibraryScanError(error);
      },
    );
  }
}

// --- Library reads (debug UI) ---------------------------------------------

/// All tracks with resolved album/artist names (title order). Backs both the
/// debug scan screen and the Library › Tracks tab. An empty search matches
/// every track while still carrying the joined artist/album names.
@riverpod
Stream<List<TrackWithMeta>> allTracks(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.searchTracks('');

// --- Library browse reads (all reactive watch() streams) -------------------

/// Every album with its artist name (name order) — the Albums grid.
@riverpod
Stream<List<AlbumWithArtist>> albums(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchAlbumsWithArtist();

/// Every artist (name order) — the Artists list.
@riverpod
Stream<List<ArtistRow>> artists(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchAllArtists();

/// An album with its tracks (disc/track order) — album detail.
@riverpod
Stream<AlbumWithTracks?> albumDetail(Ref ref, String albumId) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchAlbumWithTracks(albumId);

/// The artist row for [artistId] — resolves the album-detail header name.
@riverpod
Stream<ArtistRow?> artist(Ref ref, String artistId) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchArtist(artistId);

/// An artist with their albums (name order) — artist detail.
@riverpod
Stream<ArtistWithAlbums?> artistDetail(Ref ref, String artistId) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchArtistWithAlbums(artistId);

/// Distinct recently-played tracks (newest first) — Home strip.
@riverpod
Stream<List<TrackRow>> recentlyPlayed(Ref ref) =>
    ref.watch(vibyDatabaseProvider).historyDao.watchRecentlyPlayed(limit: 20);

/// Most-recently-added tracks — Home strip.
@riverpod
Stream<List<TrackRow>> recentlyAdded(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchRecentlyAdded();

/// Most-played tracks (by play count) — Home "Your top tracks" strip. Only
/// surfaced once there's enough history (see `shouldShowTopTracks`).
@riverpod
Stream<List<TrackRow>> topTracks(Ref ref) =>
    ref.watch(vibyDatabaseProvider).historyDao.watchMostPlayed(limit: 20);

/// Reactive total track count — drives library/Home empty states.
@riverpod
Stream<int> libraryTrackCount(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchTrackCount();

/// Count of hidden tracks (user + filter) — the Tracks-tab "N hidden" footer.
@riverpod
Stream<int> hiddenTrackCount(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchHiddenCount();

/// Tracks the user hid via "Hide song" — Hidden-songs screen.
@riverpod
Stream<List<TrackWithMeta>> hiddenByUser(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchHiddenByUser();

/// Tracks the junk filter auto-hid — Hidden-songs screen.
@riverpod
Stream<List<TrackWithMeta>> hiddenByFilter(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchHiddenByFilter();

/// Liked tracks, newest-liked first — the virtual Liked Songs collection.
@riverpod
Stream<List<TrackWithMeta>> likedTracks(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchLikedTracks();

/// Count of liked tracks — the Liked Songs card badge.
@riverpod
Stream<int> likedCount(Ref ref) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchLikedCount();

/// Whether [trackId] is liked — the heart toggle's live filled state.
@riverpod
Stream<bool> trackLiked(Ref ref, String trackId) =>
    ref.watch(vibyDatabaseProvider).libraryDao.watchLiked(trackId);

/// Debounced (300ms) full-text track search — the Search screen.
@riverpod
Stream<List<TrackWithMeta>> trackSearch(Ref ref, String query) async* {
  final String q = query.trim();
  if (q.isEmpty) {
    yield const <TrackWithMeta>[];
    return;
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  yield* ref.watch(vibyDatabaseProvider).libraryDao.searchTracks(q);
}

/// The resolved artwork directory (created once). Widgets build art paths off
/// this synchronously instead of an async lookup per image.
@Riverpod(keepAlive: true)
Future<Directory> artworkDirectory(Ref ref) =>
    ref.watch(artworkServiceProvider).directory();
