import 'dart:async';
import 'dart:developer' as developer;

import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../db/daos/library_dao.dart';
import '../../db/daos/lyrics_dao.dart';
import '../../db/tables.dart';
import '../../db/viby_database.dart';
import 'artwork_service.dart';
import 'junk_filter.dart';
import 'library_maintenance.dart';
import 'scan_diff.dart';
import 'song_mapper.dart';
import 'tag_repair_service.dart';

/// Phase of an in-flight scan.
enum ScanPhase { querying, writing, artwork, repair, done }

/// A progress tick emitted during a scan. `found`/`processed` are phase-relative
/// (tracks while writing, albums during artwork, suspicious rows during repair).
class ScanProgress {
  const ScanProgress({
    required this.phase,
    required this.found,
    required this.processed,
    this.deleted = 0,
    this.errors = 0,
    this.repaired = 0,
    this.added = 0,
    this.elapsed = Duration.zero,
  });

  final ScanPhase phase;
  final int found;
  final int processed;
  final int deleted;
  final int errors;
  final int repaired;
  final Duration elapsed;

  /// Newly-added tracks this scan (incremental only; 0 on a full scan). Drives
  /// the "N songs added" auto-detection snackbar.
  final int added;
}

/// Scans on-device audio (via on_audio_query) into the library DB.
///
/// Guarantees: only one scan runs at a time (guarded by [_scanning]); scans are
/// cancelable ([cancel]); all writes go through [LibraryDao] batches/transactions;
/// the library becomes browsable before artwork extraction (a later phase).
class LocalScanner {
  LocalScanner({
    required OnAudioQuery audioQuery,
    required LibraryDao libraryDao,
    required ArtworkService artworkService,
    required LibraryMaintenance maintenance,
    TagRepairService? tagRepair,
    LyricsDao? lyricsDao,
    this.chunkSize = 500,
    this.minDurationMs = kMinTrackDurationMs,
  }) : _audioQuery = audioQuery,
       _libraryDao = libraryDao,
       _artworkService = artworkService,
       _maintenance = maintenance,
       _tagRepair = tagRepair,
       _lyricsDao = lyricsDao;

  final OnAudioQuery _audioQuery;
  final LibraryDao _libraryDao;
  final ArtworkService _artworkService;

  /// The shared purge path. A track that vanished from MediaStore gets exactly
  /// the same cleanup as one the user deleted from the device (playlist entries,
  /// empty albums/artists, orphaned artwork) — see [LibraryMaintenance].
  final LibraryMaintenance _maintenance;
  final TagRepairService? _tagRepair;

  /// Optional lyrics cache — when a track's file changed, its cached lyrics are
  /// dropped so they re-resolve on next play (deleted tracks cascade already).
  final LyricsDao? _lyricsDao;
  final int chunkSize;
  final int minDurationMs;

  bool _scanning = false;
  bool _cancelled = false;

  bool get isScanning => _scanning;

  /// Requests the current scan stop at the next checkpoint.
  void cancel() => _cancelled = true;

  /// Full (re)scan: every non-junk song is upserted.
  Stream<ScanProgress> fullScan() => _run(incremental: false);

  /// Incremental rescan: only new/changed songs are upserted and songs removed
  /// from MediaStore are deleted (local rows only).
  Stream<ScanProgress> incrementalRescan() => _run(incremental: true);

  Stream<ScanProgress> _run({required bool incremental}) {
    if (_scanning) return const Stream<ScanProgress>.empty();
    _scanning = true;
    _cancelled = false;
    final StreamController<ScanProgress> controller =
        StreamController<ScanProgress>();
    unawaited(() async {
      try {
        await _scan(incremental: incremental, out: controller);
      } catch (error, stack) {
        developer.log('scan failed', name: 'viby.scanner', error: error, stackTrace: stack);
        controller.addError(error, stack);
      } finally {
        _scanning = false;
        await controller.close();
      }
    }());
    return controller.stream;
  }

  Future<void> _scan({
    required bool incremental,
    required StreamController<ScanProgress> out,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    // 1. QUERY
    out.add(const ScanProgress(
      phase: ScanPhase.querying,
      found: 0,
      processed: 0,
    ));
    // Gate on the plugin's OWN permission view (READ_MEDIA_AUDIO +
    // READ_MEDIA_IMAGES on API 33+). If it's not satisfied, querySongs takes a
    // buggy no-permission path that double-replies and crashes the app
    // natively — so we must never reach it without this check passing.
    if (!await _audioQuery.permissionsStatus()) {
      throw StateError(
        'Audio library permission not granted (on_audio_query requires '
        'READ_MEDIA_AUDIO + READ_MEDIA_IMAGES on Android 13+).',
      );
    }
    final List<SongModel> all = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
    // Hard-drop only trivially-short blips (<5s) — never stored. Everything
    // else is kept and *scored*: recordings/ringtones are stored hidden
    // (hiddenByFilter), not dropped, so a false positive stays recoverable.
    final List<SongModel> songs = all
        .where((SongModel s) => !isTooShort(s.duration ?? 0,
            minDurationMs: minDurationMs))
        .toList();
    developer.log(
      'query: ${songs.length} entries kept (>=${minDurationMs}ms) of '
      '${all.length} raw',
      name: 'viby.scanner',
    );
    out.add(ScanProgress(
      phase: ScanPhase.querying,
      found: songs.length,
      processed: 0,
    ));
    if (_cancelled) {
      out.add(_doneProgress(0, 0, 0, 0, stopwatch));
      return;
    }

    // 2. DIFF (incremental only)
    List<SongModel> toWrite = songs;
    List<String> toDelete = const <String>[];
    int addedCount = 0;
    if (incremental) {
      final List<MediaSnapshotEntry> media = songs
          .map((SongModel s) => MediaSnapshotEntry(
                id: localTrackId(s.id),
                dateModified: s.dateModified ?? 0,
              ))
          .toList();
      final List<DbSnapshotEntry> dbSnapshot =
          (await _libraryDao.trackSnapshots())
              .map(
                (r) => DbSnapshotEntry(
                  id: r.id,
                  dateModified: r.dateModified.millisecondsSinceEpoch ~/ 1000,
                  source: r.source,
                ),
              )
              .toList();
      final ScanDiff diff = computeScanDiff(media, dbSnapshot);
      final Set<String> upsertIds = diff.upserts;
      toWrite = songs
          .where((SongModel s) => upsertIds.contains(localTrackId(s.id)))
          .toList();
      toDelete = diff.deleted.toList();
      addedCount = diff.added.length;
      // A changed file may have gained/edited lyrics — drop its cache so they
      // re-resolve on next play (deleted tracks cascade their lyrics away).
      if (diff.changed.isNotEmpty) {
        await _lyricsDao?.deleteForTracks(diff.changed);
      }
      developer.log(
        'diff: ${diff.added.length} added, ${diff.changed.length} changed, '
        '${diff.deleted.length} deleted',
        name: 'viby.scanner',
      );
    }

    // 3. WRITE (artists + albums first, then tracks in chunks)
    final Set<String> affectedAlbumIds = <String>{};
    final Map<String, int> albumMediaIds = <String, int>{};
    final Map<String, ArtistsCompanion> artists = <String, ArtistsCompanion>{};
    final Map<String, AlbumsCompanion> albums = <String, AlbumsCompanion>{};
    for (final SongModel s in toWrite) {
      artists[artistIdForSong(s)] = songToArtistCompanion(s);
      final String albumId = albumIdForSong(s);
      albums[albumId] = songToAlbumCompanion(s);
      affectedAlbumIds.add(albumId);
      if (s.albumId != null) albumMediaIds[albumId] = s.albumId!;
    }
    await _libraryDao.upsertArtists(artists.values.toList());
    await _libraryDao.upsertAlbums(albums.values.toList());

    // Load the flags of any rows we're about to overwrite so a rescan preserves
    // the user's like + hide/unhide choices (see [resolveVisibility]).
    final Map<String, TrackFlags> existingFlags = <String, TrackFlags>{
      for (final MapEntry<String,
              ({TrackVisibility visibility, bool userOverride, bool liked, DateTime? likedAt})>
          e in (await _libraryDao.trackFlags(
        toWrite.map((SongModel s) => localTrackId(s.id)).toList(),
      ))
              .entries)
        e.key: TrackFlags(
          visibility: e.value.visibility,
          userOverride: e.value.userOverride,
          liked: e.value.liked,
          likedAt: e.value.likedAt,
        ),
    };

    int processed = 0;
    out.add(ScanProgress(
      phase: ScanPhase.writing,
      found: toWrite.length,
      processed: 0,
    ));
    for (final List<SongModel> chunk in _chunk(toWrite, chunkSize)) {
      if (_cancelled) break;
      await _libraryDao.upsertTracks(
        chunk.map((SongModel s) => _companionFor(s, existingFlags)).toList(),
      );
      processed += chunk.length;
      out.add(ScanProgress(
        phase: ScanPhase.writing,
        found: toWrite.length,
        processed: processed,
      ));
    }

    if (toDelete.isNotEmpty) await _maintenance.purgeTracks(toDelete);
    await _libraryDao.recomputeAlbumTrackCounts(affectedAlbumIds);

    // 4. ARTWORK (after the library is browsable)
    int artworkErrors = 0;
    if (!_cancelled) {
      final List<String> albumIds = albumMediaIds.keys.toList();
      out.add(ScanProgress(
        phase: ScanPhase.artwork,
        found: albumIds.length,
        processed: 0,
        deleted: toDelete.length,
      ));
      int done = 0;
      for (final String albumId in albumIds) {
        if (_cancelled) break;
        try {
          final bool hasArt = await _artworkService.ensureAlbumArtwork(
            mediaAlbumId: albumMediaIds[albumId]!,
            artworkKey: albumId,
          );
          if (hasArt) await _libraryDao.setAlbumArtwork(albumId, albumId);
        } catch (_) {
          artworkErrors++;
        }
        done++;
        out.add(ScanProgress(
          phase: ScanPhase.artwork,
          found: albumIds.length,
          processed: done,
          deleted: toDelete.length,
          errors: artworkErrors,
        ));
      }
    }

    // 5. REPAIR (mojibake tag re-decode; optional post-scan phase)
    int repaired = 0;
    final TagRepairService? repair = _tagRepair;
    if (repair != null && !_cancelled) {
      out.add(const ScanProgress(
        phase: ScanPhase.repair,
        found: 0,
        processed: 0,
      ));
      try {
        final RepairResult result = await repair.repairAll(
          onProgress: (RepairProgress p) => out.add(ScanProgress(
            phase: ScanPhase.repair,
            found: p.found,
            processed: p.processed,
            deleted: toDelete.length,
            errors: artworkErrors,
          )),
        );
        repaired = result.repaired;
        developer.log(
          'repair: ${result.repaired} of ${result.suspicious} suspicious '
          'strings fixed in ${result.elapsed.inMilliseconds}ms',
          name: 'viby.scanner',
        );
      } catch (error, stack) {
        // A repair failure must never abort an otherwise-successful scan.
        developer.log('tag repair failed', name: 'viby.scanner', error: error, stackTrace: stack);
      }
    }

    // 6. DONE
    developer.log(
      'done: wrote $processed tracks, deleted ${toDelete.length}, '
      '$artworkErrors artwork errors, $repaired tags repaired, '
      '${stopwatch.elapsedMilliseconds}ms${_cancelled ? ' (cancelled)' : ''}',
      name: 'viby.scanner',
    );
    out.add(_doneProgress(
      processed,
      toDelete.length,
      artworkErrors,
      repaired,
      stopwatch,
      added: addedCount,
    ));
  }

  /// Builds a track's upsert row with its resolved visibility and any preserved
  /// like/hide flags from an existing row.
  TracksCompanion _companionFor(
    SongModel song,
    Map<String, TrackFlags> existingFlags,
  ) {
    final TrackFlags? existing = existingFlags[localTrackId(song.id)];
    final bool filterHidden = isFilterHidden(junkSignalsFromSong(song));
    final TrackVisibility visibility =
        resolveVisibility(existing: existing, filterHidden: filterHidden);
    return songToTrackCompanion(
      song,
      visibility: visibility,
      userOverride: existing?.userOverride ?? false,
      liked: existing?.liked ?? false,
      likedAt: existing?.likedAt,
    );
  }

  ScanProgress _doneProgress(
    int tracks,
    int deleted,
    int errors,
    int repaired,
    Stopwatch stopwatch, {
    int added = 0,
  }) {
    return ScanProgress(
      phase: ScanPhase.done,
      found: tracks,
      processed: tracks,
      deleted: deleted,
      errors: errors,
      repaired: repaired,
      added: added,
      elapsed: stopwatch.elapsed,
    );
  }

  Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (int i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}
