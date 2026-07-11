import '../../models/track.dart';
import '../lyrics_repository.dart';

/// Reads a `.lrc` sidecar sitting next to the audio file (same basename) or in a
/// `<musicRoot>/Lyrics/` folder. Because a `.lrc` is a *non-media* file, scoped
/// storage on Android 13+ blocks a plain `File()` read; the real implementation
/// (Stage 3) resolves it through a user-granted SAF tree. This interface keeps
/// the repository agnostic to how the bytes are obtained.
abstract interface class SidecarLyricsSource implements LyricsSourceResolver {}

/// The sidecar source used until the user grants a lyrics folder — always misses,
/// so resolution falls through to embedded lyrics. Swapped for the SAF-backed
/// implementation once a folder is granted (Stage 3).
class NoopSidecarSource implements SidecarLyricsSource {
  const NoopSidecarSource();

  @override
  Future<RawLyrics?> resolve(Track track) async => null;
}
