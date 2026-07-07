import 'dart:io';
import 'dart:typed_data';

import '../../../core/tag_encoding.dart';
import '../../db/daos/library_dao.dart';
import '../../db/viby_database.dart';
import 'id3_reader.dart';

/// Reads raw ID3 tags off disk. Abstracted so the repair pass is testable
/// (inject a fake) and can degrade gracefully where file access isn't possible.
abstract interface class RawTagReader {
  /// Returns the file's tags, or null if it can't be read.
  Future<Id3Tags?> read(String path);
}

/// Default [RawTagReader]: reads the file's head (where ID3v2 lives) and tail
/// (where ID3v1 lives) and parses them with [Id3Reader]. Never throws.
class FileId3TagReader implements RawTagReader {
  const FileId3TagReader({this.headBytes = 128 * 1024});

  /// How much of the file head to read (ID3v2 tags are near the front).
  final int headBytes;

  @override
  Future<Id3Tags?> read(String path) async {
    try {
      final File file = File(path);
      if (!file.existsSync()) return null;
      final int len = await file.length();
      final RandomAccessFile raf = await file.open();
      try {
        final int headLen = len < headBytes ? len : headBytes;
        final Uint8List head =
            await raf.read(headLen) as Uint8List? ?? Uint8List(0);
        final Id3Tags v2 = Id3Reader.parse(head);
        if (v2.title != null && v2.artist != null && v2.album != null) {
          return v2;
        }
        // Also grab the last 128 bytes for an ID3v1 fallback.
        Uint8List tail = Uint8List(0);
        if (len >= 128) {
          await raf.setPosition(len - 128);
          tail = await raf.read(128) as Uint8List? ?? Uint8List(0);
        }
        final Id3Tags v1 = Id3Reader.parse(tail);
        return Id3Tags(
          title: v2.title ?? v1.title,
          artist: v2.artist ?? v1.artist,
          album: v2.album ?? v1.album,
        );
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Progress tick for the repair pass (`processed` of `found` suspicious rows).
class RepairProgress {
  const RepairProgress({required this.found, required this.processed});
  final int found;
  final int processed;
}

/// Outcome of a repair pass.
class RepairResult {
  const RepairResult({
    required this.suspicious,
    required this.repaired,
    required this.elapsed,
  });

  final int suspicious;
  final int repaired;
  final Duration elapsed;
}

/// Repairs mojibake title/album/artist strings caused by legacy-codepage tags
/// (Windows-1256 declared as Latin-1). It never touches files on disk — only the
/// DB rows are updated.
///
/// Two-stage per suspicious value:
///  1. **String re-decode** ([bestDecoding]) — fixes the common case where
///     MediaStore decoded CP1256 bytes as Latin-1 (bytes preserved, recoverable
///     without I/O).
///  2. **File re-read** (tracks only, when a [RawTagReader] is supplied and the
///     DB string is lossy — has `?`/U+FFFD) — pulls the raw Latin-1 frame bytes
///     back off disk and re-decodes those. Recovers cases MediaStore mangled.
class TagRepairService {
  TagRepairService(this._libraryDao, {RawTagReader? tagReader})
      : _tagReader = tagReader;

  final LibraryDao _libraryDao;
  final RawTagReader? _tagReader;

  /// Runs the repair over every track/album/artist. Reports [onProgress] as it
  /// works. Idempotent: re-running finds nothing left to fix.
  Future<RepairResult> repairAll({
    void Function(RepairProgress progress)? onProgress,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final List<TrackRow> trackRows = await _libraryDao.allTrackRows();
    final List<AlbumRow> albumRows = await _libraryDao.allAlbumRows();
    final List<ArtistRow> artistRows = await _libraryDao.allArtistRows();

    final List<TrackRow> suspectTracks =
        trackRows.where((TrackRow t) => looksSuspicious(t.title)).toList();
    final List<AlbumRow> suspectAlbums =
        albumRows.where((AlbumRow a) => looksSuspicious(a.name)).toList();
    final List<ArtistRow> suspectArtists =
        artistRows.where((ArtistRow a) => looksSuspicious(a.name)).toList();

    final int found =
        suspectTracks.length + suspectAlbums.length + suspectArtists.length;
    int processed = 0;
    void tick() => onProgress?.call(
          RepairProgress(found: found, processed: ++processed),
        );

    final Map<String, String> trackTitles = <String, String>{};
    final Map<String, String> albumNames = <String, String>{};
    final Map<String, String> artistNames = <String, String>{};

    for (final TrackRow t in suspectTracks) {
      final String? fixed = await _repairTitle(t);
      if (fixed != null && fixed != t.title) trackTitles[t.id] = fixed;
      tick();
    }
    for (final AlbumRow a in suspectAlbums) {
      final String fixed = bestDecoding(a.name);
      if (fixed != a.name) albumNames[a.id] = fixed;
      tick();
    }
    for (final ArtistRow a in suspectArtists) {
      final String fixed = bestDecoding(a.name);
      if (fixed != a.name) artistNames[a.id] = fixed;
      tick();
    }

    await _libraryDao.applyTagRepairs(
      trackTitles: trackTitles,
      albumNames: albumNames,
      artistNames: artistNames,
    );

    sw.stop();
    return RepairResult(
      suspicious: found,
      repaired: trackTitles.length + albumNames.length + artistNames.length,
      elapsed: sw.elapsed,
    );
  }

  /// Best repair for a track title: string re-decode first; if that leaves it
  /// unchanged and the value is *lossy* (has `?`/U+FFFD), fall back to re-reading
  /// the raw frame bytes off disk (when a reader + file path are available).
  Future<String?> _repairTitle(TrackRow t) async {
    final String viaString = bestDecoding(t.title);
    if (viaString != t.title) return viaString;
    if (!_isLossy(t.title)) return null;
    final RawTagReader? reader = _tagReader;
    final String? path = t.filePath;
    if (reader == null || path == null) return null;
    final Id3Tags? tags = await reader.read(path);
    final String? raw = tags?.title;
    if (raw == null || raw.isEmpty) return null;
    final String fixed = bestDecoding(raw);
    return fixed.isEmpty ? null : fixed;
  }

  /// A value is lossy when MediaStore replaced bytes with `?`/U+FFFD, so the
  /// original can only come back from the file itself.
  static bool _isLossy(String s) =>
      s.contains('�') || RegExp(r'\?{2,}').hasMatch(s);
}
