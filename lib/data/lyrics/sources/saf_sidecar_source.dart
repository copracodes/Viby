import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../db/tables.dart' show LyricsSource;
import '../../models/track.dart';
import '../lrc_parser.dart';
import '../lyrics_repository.dart';
import '../lyrics_saf_channel.dart';
import 'sidecar_lyrics_source.dart';

/// Reads a `.lrc` sidecar through a user-granted SAF folder ([treeUri]).
///
/// Candidates (native tries in order): the same-directory `.lrc` (same basename
/// as the audio file) and `<grantedRoot>/Lyrics/<basename>.lrc`. Bytes are
/// decoded via [LrcParser.decodeBytes] (BOM strip + CP1256 fallback), so a
/// legacy Arabic `.lrc` recovers through the same pathway as everything else.
class SafSidecarSource implements SidecarLyricsSource {
  const SafSidecarSource({required this.treeUri, required LyricsSafBridge bridge})
      : _bridge = bridge;

  final String treeUri;
  final LyricsSafBridge _bridge;

  @override
  Future<RawLyrics?> resolve(Track track) async {
    final String? path = track.filePath;
    if (path == null) return null; // subsonic tracks have no local sidecar
    // MediaStore file paths are always POSIX (`/`-separated), so use the posix
    // context explicitly — the default context would use `\` off Windows tests.
    final String base = p.posix.basenameWithoutExtension(path);
    if (base.isEmpty) return null;
    final String sidecarName = '$base.lrc';
    final String absPath = p.posix.join(p.posix.dirname(path), sidecarName);

    final Uint8List? bytes = await _bridge.readSidecar(
      treeUri: treeUri,
      absPath: absPath,
      sidecarName: sidecarName,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final String text = LrcParser.decodeBytes(bytes);
    if (text.trim().isEmpty) return null;
    return RawLyrics(text: text, source: LyricsSource.sidecarLrc);
  }
}

/// A friendly display name for a granted tree URI (e.g. `Music` from
/// `content://…/tree/primary%3AMusic`). Falls back to the raw last segment.
String prettyTreeUriName(String treeUri) {
  final Uri? uri = Uri.tryParse(treeUri);
  if (uri == null) return treeUri;
  final List<String> segments = uri.pathSegments;
  if (segments.isEmpty) return treeUri;
  final String last = Uri.decodeComponent(segments.last); // e.g. "primary:Music"
  final int colon = last.indexOf(':');
  final String tail = colon >= 0 ? last.substring(colon + 1) : last;
  if (tail.isEmpty) return 'Internal storage';
  final List<String> parts = tail.split('/');
  return parts.isEmpty ? tail : parts.last;
}
