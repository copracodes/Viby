import 'dart:io';
import 'dart:typed_data';

import '../../db/tables.dart' show LyricsSource;
import '../../models/track.dart';
import '../../sources/local/id3_reader.dart';
import '../lyrics_repository.dart';

/// Reads the full ID3v2 tag off disk. Abstracted so the embedded source is
/// testable (inject a fake) and so a future Vorbis/FLAC reader can slot in.
abstract interface class Id3TagBytesReader {
  /// The complete ID3v2 tag bytes (header + declared tag size), or null if the
  /// file has no ID3v2 tag / can't be read.
  Future<Uint8List?> readId3Tag(String path);
}

/// Default reader: reads the 10-byte ID3v2 header, computes the synchsafe tag
/// size, then reads exactly that many bytes — so a USLT frame that sits *after*
/// a large embedded cover (APIC) is still captured. Never throws.
class FileId3TagBytesReader implements Id3TagBytesReader {
  const FileId3TagBytesReader();

  @override
  Future<Uint8List?> readId3Tag(String path) async {
    try {
      final File file = File(path);
      if (!file.existsSync()) return null;
      final RandomAccessFile raf = await file.open();
      try {
        final Uint8List header = await raf.read(10);
        if (header.length < 10 ||
            header[0] != 0x49 ||
            header[1] != 0x44 ||
            header[2] != 0x33) {
          return null; // no "ID3" magic
        }
        final int tagSize = (header[6] << 21) |
            (header[7] << 14) |
            (header[8] << 7) |
            header[9];
        final int total = (10 + tagSize).clamp(0, await file.length());
        await raf.setPosition(0);
        return await raf.read(total);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Resolves lyrics embedded in the audio file's ID3v2 tag: a synced `SYLT` frame
/// (rare — serialized to LRC text) is preferred, else an unsynced `USLT` frame.
/// A `USLT` body that itself contains `[mm:ss.xx]` timestamps parses as synced
/// downstream, so many "unsynced" frames still light up the scrolling view.
class EmbeddedLyricsSource implements LyricsSourceResolver {
  EmbeddedLyricsSource({Id3TagBytesReader? reader})
      : _reader = reader ?? const FileId3TagBytesReader();

  final Id3TagBytesReader _reader;

  @override
  Future<RawLyrics?> resolve(Track track) async {
    final String? path = track.filePath;
    if (path == null) return null; // subsonic tracks have no local file
    final Uint8List? tag = await _reader.readId3Tag(path);
    if (tag == null) return null;
    final EmbeddedLyrics emb = Id3Reader.parseLyrics(tag);
    if (emb.isEmpty) return null;

    final List<SyltEntry>? synced = emb.syncedEntries;
    if (synced != null && synced.isNotEmpty) {
      return RawLyrics(
        text: syltToLrc(synced),
        source: LyricsSource.embeddedSynced,
      );
    }
    final String? unsynced = emb.unsyncedText;
    if (unsynced != null && unsynced.isNotEmpty) {
      return RawLyrics(
        text: unsynced,
        source: LyricsSource.embeddedUnsynced,
      );
    }
    return null;
  }
}

/// Serializes SYLT millisecond entries into LRC text (`[mm:ss.xx]line`) so the
/// repository can parse embedded synced lyrics through the same [bestDecoding]-
/// aware path as sidecar `.lrc`. Latin-1 SYLT text arrives byte-preserved, so
/// legacy CP1256 survives into the parser.
String syltToLrc(List<SyltEntry> entries) {
  final StringBuffer sb = StringBuffer();
  for (final SyltEntry e in entries) {
    final int totalCs = e.timeMs ~/ 10; // centiseconds
    final int minutes = totalCs ~/ 6000;
    final int seconds = (totalCs ~/ 100) % 60;
    final int cs = totalCs % 100;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    final String cc = cs.toString().padLeft(2, '0');
    // SYLT text often includes a leading newline separator; trim per line.
    sb.writeln('[$mm:$ss.$cc]${e.text.replaceAll('\n', '').trim()}');
  }
  return sb.toString();
}
