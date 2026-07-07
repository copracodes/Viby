import 'dart:io';
import 'dart:typed_data';

import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Extracts and caches album artwork on disk.
///
/// Art lives at `<appSupport>/artwork/<safeKey>.jpg`, where the key is the
/// album's deterministic id (`local:album:<id>`). Colons aren't filesystem-safe
/// everywhere, so the on-disk name is sanitised while the DB `artworkKey`
/// keeps the logical id.
class ArtworkService {
  ArtworkService(this._audioQuery, {int size = 600}) : _size = size;

  final OnAudioQuery _audioQuery;
  final int _size;
  Directory? _cachedDir;

  Future<Directory> _artworkDir() async {
    final Directory? cached = _cachedDir;
    if (cached != null) return cached;
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'artwork'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// The on-disk file name for [artworkKey] (colons aren't filesystem-safe).
  /// Public + static so UI can build the path synchronously once it has the
  /// [directory].
  static String fileNameFor(String artworkKey) =>
      '${artworkKey.replaceAll(':', '_')}.jpg';

  /// The artwork directory (created on first use). Exposed so widgets can
  /// resolve art paths without an async call per image.
  Future<Directory> directory() => _artworkDir();

  Future<File> fileFor(String artworkKey) async =>
      File(p.join((await _artworkDir()).path, fileNameFor(artworkKey)));

  Future<bool> hasArtwork(String artworkKey) async =>
      (await fileFor(artworkKey)).exists();

  /// The on-disk artwork path for [artworkKey] if the file exists, else null.
  /// Used to hand a resolved `file://` art URI to the media session.
  Future<String?> resolvedPath(String artworkKey) async {
    final File file = await fileFor(artworkKey);
    return file.existsSync() ? file.path : null;
  }

  /// Extracts album art for [mediaAlbumId] and writes it under [artworkKey],
  /// but only if not already on disk (keeps rescans cheap). Returns true if art
  /// exists on disk afterwards. Throws are the caller's to catch so one bad
  /// image can't abort a scan.
  Future<bool> ensureAlbumArtwork({
    required int mediaAlbumId,
    required String artworkKey,
  }) async {
    final File file = await fileFor(artworkKey);
    if (file.existsSync()) return true;
    final Uint8List? bytes = await _audioQuery.queryArtwork(
      mediaAlbumId,
      ArtworkType.ALBUM,
      format: ArtworkFormat.JPEG,
      size: _size,
    );
    if (bytes == null || bytes.isEmpty) return false;
    await file.writeAsBytes(bytes, flush: true);
    return true;
  }
}
