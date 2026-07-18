/// Deriving an artist "portrait" from their albums, offline and pure.
///
/// There is no artist-image source in the library, so the portrait is borrowed
/// from one of the artist's own albums. [pickArtistArtworkKey] is the selection
/// rule (unit-tested); the DAO gathers the candidates and a provider caches the
/// result per artist.
library;

/// One of an artist's albums, with the signals the picker ranks on.
class ArtistArtCandidate {
  const ArtistArtCandidate({
    required this.albumId,
    required this.name,
    required this.artworkKey,
    required this.trackCount,
    required this.playCount,
  });

  final String albumId;
  final String name;

  /// The album's artwork key, or null when it has no art (then it can't be the
  /// portrait).
  final String? artworkKey;

  /// Visible tracks in the album — the second-order tiebreak (a fuller album is
  /// a better representative than a single).
  final int trackCount;

  /// Total plays across the album's tracks — the primary signal.
  final int playCount;
}

/// The artwork key for an artist's portrait: the art of their **most-played**
/// album, then (tie) the album with the most tracks, then (tie) the first
/// alphabetically. Albums without art are ignored; null when the artist has no
/// album with art (the UI then falls back to the letter avatar).
String? pickArtistArtworkKey(List<ArtistArtCandidate> albums) {
  final List<ArtistArtCandidate> withArt = albums
      .where((ArtistArtCandidate a) => a.artworkKey != null)
      .toList();
  if (withArt.isEmpty) return null;
  withArt.sort((ArtistArtCandidate a, ArtistArtCandidate b) {
    if (a.playCount != b.playCount) return b.playCount.compareTo(a.playCount);
    if (a.trackCount != b.trackCount) {
      return b.trackCount.compareTo(a.trackCount);
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return withArt.first.artworkKey;
}
