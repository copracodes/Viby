/// Pure metadata cleanup for online lyrics lookups — garbage in = wrong lyrics
/// out. Strips the tag noise that MediaStore titles carry (feat./remaster/live/
/// deluxe suffixes, "- Single", featured + multi-artist fields) so the query
/// matches LRCLIB's canonical track/artist. Originals stay for display; these
/// cleaned strings are used *only* for the network query.
library;

/// A cleaned query for an online lyrics lookup.
class LyricsQuery {
  const LyricsQuery({required this.track, required this.artist, this.album});

  /// Cleaned track title (noise stripped).
  final String track;

  /// Primary artist (featured / collaborating artists removed).
  final String artist;

  /// Cleaned album, or null when unknown / not useful.
  final String? album;

  bool get isUsable => track.isNotEmpty && artist.isNotEmpty;

  @override
  String toString() => 'LyricsQuery(track: "$track", artist: "$artist", '
      'album: ${album == null ? 'null' : '"$album"'})';
}

/// Parenthetical/bracketed noise removed from a title, applied in order. Each
/// matches a `(…)` or `[…]` group containing the keyword.
final List<RegExp> _bracketNoise = <RegExp>[
  RegExp(r'\s*[\(\[][^\)\]]*\b(feat|ft|featuring|with)\b\.?[^\)\]]*[\)\]]',
      caseSensitive: false),
  RegExp(r'\s*[\(\[][^\)\]]*\bre-?master(ed)?\b[^\)\]]*[\)\]]',
      caseSensitive: false),
  RegExp(r'\s*[\(\[][^\)\]]*\blive\b[^\)\]]*[\)\]]', caseSensitive: false),
  RegExp(
      r'\s*[\(\[][^\)\]]*\b(deluxe|expanded|anniversary|bonus|reissue)\b[^\)\]]*[\)\]]',
      caseSensitive: false),
  RegExp(
      r'\s*[\(\[][^\)\]]*\b(acoustic|radio edit|mono|stereo|single version|album version|original mix)\b[^\)\]]*[\)\]]',
      caseSensitive: false),
];

/// Trailing "` - suffix`" noise (dash-delimited), anchored to end of string.
final RegExp _trailingDashNoise = RegExp(
  r'\s*-\s*(single|ep|re-?master(ed)?|\d{4}\s*re-?master(ed)?|remastered\s*\d{4}|live|deluxe.*|bonus track|radio edit|mono|stereo)\s*$',
  caseSensitive: false,
);

/// A bare (no-bracket) `feat.`/`ft.`/`featuring` run to end of string.
final RegExp _inlineFeat =
    RegExp(r'\s+(feat|ft|featuring)\.?\s+.*$', caseSensitive: false);

/// Collaboration separators in an artist field; the primary is everything
/// before the first match.
final RegExp _artistSeparator = RegExp(
  r'\s*(,|&|;|/|\bx\b|×|\bvs\.?\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b)\s*',
  caseSensitive: false,
);

/// Empty leftover brackets after noise removal.
final RegExp _emptyBrackets = RegExp(r'[\(\[]\s*[\)\]]');

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The literal MediaStore reports for missing metadata (see `DisplayNames`).
const String _kUnknown = '<unknown>';

/// Cleans a title for querying: strips bracketed + trailing + inline noise.
String cleanTitle(String title) {
  String out = title;
  for (final RegExp re in _bracketNoise) {
    out = out.replaceAll(re, '');
  }
  out = out.replaceAll(_trailingDashNoise, '');
  out = out.replaceAll(_inlineFeat, '');
  out = out.replaceAll(_emptyBrackets, '');
  return _collapse(out);
}

/// The primary artist: featured artists dropped, split on the first
/// collaboration separator.
String primaryArtist(String artist) {
  if (artist.trim().isEmpty || artist.trim() == _kUnknown) return '';
  String out = artist.replaceAll(_inlineFeat, '');
  final RegExpMatch? m = _artistSeparator.firstMatch(out);
  if (m != null) out = out.substring(0, m.start);
  return _collapse(out);
}

/// Builds a cleaned [LyricsQuery] from raw track metadata. An unknown/empty
/// album is dropped (null) so it never narrows a match wrongly.
LyricsQuery cleanLyricsQuery({
  required String title,
  required String artist,
  String? album,
}) {
  final String? cleanedAlbum =
      (album == null || album.trim().isEmpty || album.trim() == _kUnknown)
          ? null
          : _collapse(album);
  return LyricsQuery(
    track: cleanTitle(title),
    artist: primaryArtist(artist),
    album: cleanedAlbum,
  );
}
