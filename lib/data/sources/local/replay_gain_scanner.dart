import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../../db/daos/library_dao.dart';
import '../../db/viby_database.dart';
import 'id3_reader.dart';

/// Reads a file's ReplayGain tags. A seam so the scan phase is testable without
/// touching the disk (and so a platform that can't read files degrades to nulls).
abstract interface class RawReplayGainReader {
  Future<ReplayGainTags?> read(String path);
}

/// Default reader: pulls the file's head (ID3v2 lives at the front) and parses
/// it with the dependency-free [Id3Reader]. Never throws — an unreadable file is
/// simply "no tags".
class FileReplayGainReader implements RawReplayGainReader {
  const FileReplayGainReader({this.headBytes = 128 * 1024});

  final int headBytes;

  @override
  Future<ReplayGainTags?> read(String path) async {
    try {
      final File file = File(path);
      if (!file.existsSync()) return null;
      final int len = await file.length();
      final RandomAccessFile raf = await file.open();
      try {
        final int headLen = len < headBytes ? len : headBytes;
        final Uint8List head =
            await raf.read(headLen) as Uint8List? ?? Uint8List(0);
        return Id3Reader.parseReplayGain(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Progress of the ReplayGain phase.
class ReplayGainProgress {
  const ReplayGainProgress({required this.found, required this.processed});

  final int found;
  final int processed;
}

/// Fills in the ReplayGain columns for tracks that haven't been examined yet.
///
/// Runs as a post-scan phase rather than inline with the MediaStore write,
/// because it is the only part of scanning that must *open every file*: folding
/// it into the main write would put ~10k file reads between the user and a
/// browsable library. As a separate phase the library appears first and the
/// gains fill in behind it; and because `rgScanned` marks a file as examined,
/// each file is read exactly once — untagged files are not re-read on every
/// scan (which is why "no tags" and "not looked at" are distinct states).
class ReplayGainScanner {
  ReplayGainScanner(
    this._dao, {
    RawReplayGainReader reader = const FileReplayGainReader(),
    this.chunkSize = 100,
  }) : _reader = reader;

  final LibraryDao _dao;
  final RawReplayGainReader _reader;
  final int chunkSize;

  /// Reads tags for every not-yet-examined local track with a file path.
  /// Returns how many tracks actually carried gain tags.
  Future<int> scanPending({
    void Function(ReplayGainProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final List<TrackRow> pending = await _dao.tracksMissingReplayGain();
    if (pending.isEmpty) return 0;

    int processed = 0;
    int tagged = 0;
    onProgress?.call(
      ReplayGainProgress(found: pending.length, processed: 0),
    );

    final List<TrackReplayGain> batch = <TrackReplayGain>[];
    for (final TrackRow row in pending) {
      if (isCancelled?.call() ?? false) break;
      final String? path = row.filePath;
      final ReplayGainTags? tags =
          path == null ? null : await _reader.read(path);
      if (tags != null && !tags.isEmpty) tagged++;
      batch.add(
        TrackReplayGain(
          id: row.id,
          trackGainDb: tags?.trackGainDb,
          trackPeak: tags?.trackPeak,
          albumGainDb: tags?.albumGainDb,
          albumPeak: tags?.albumPeak,
        ),
      );
      processed++;
      if (batch.length >= chunkSize) {
        await _dao.writeReplayGain(batch);
        batch.clear();
        onProgress?.call(
          ReplayGainProgress(found: pending.length, processed: processed),
        );
      }
    }
    if (batch.isNotEmpty) await _dao.writeReplayGain(batch);
    onProgress?.call(
      ReplayGainProgress(found: pending.length, processed: processed),
    );

    developer.log(
      'replaygain: examined $processed files, $tagged carried tags',
      name: 'viby.scanner',
    );
    return tagged;
  }
}
