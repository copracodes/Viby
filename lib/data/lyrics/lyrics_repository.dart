import '../db/daos/lyrics_dao.dart';
import '../db/viby_database.dart' show LyricsRow;
import '../models/track.dart';
import 'lrc_parser.dart';
import 'lyrics.dart';

/// Raw (unparsed) lyrics fetched by a [LyricsSourceResolver], plus where they
/// came from. The repository parses [text] with [LrcParser]; a synced embedded
/// SYLT frame is serialized to LRC text upstream so parsing is uniform.
class RawLyrics {
  const RawLyrics({required this.text, required this.source});
  final String text;
  final LyricsSource source;
}

/// One link in the resolution chain. Returns null when it has nothing for the
/// track (the repository then tries the next source in priority order).
abstract interface class LyricsSourceResolver {
  Future<RawLyrics?> resolve(Track track);
}

/// Resolves, parses, and caches lyrics per track.
///
/// Resolution priority is the order of [sources] (sidecar `.lrc` → embedded
/// synced → embedded unsynced); the first non-empty hit wins and is cached in
/// drift. A miss caches a [LyricsSource.none] negative marker so we don't hit
/// disk on every play — cleared by [refresh] or a rescan (which drops the row
/// when the file's `dateModified` changes). Cached rows store the raw text and
/// are re-parsed on read, so the parser can evolve without a migration.
class LyricsRepository {
  LyricsRepository({
    required LyricsDao dao,
    required List<LyricsSourceResolver> sources,
  })  : _dao = dao,
        _sources = sources;

  final LyricsDao _dao;
  final List<LyricsSourceResolver> _sources;

  /// Lyrics for [track], from cache when present. Pass [refresh] to bypass and
  /// re-resolve (used after a manual "Refresh lyrics").
  Future<Lyrics> lyricsFor(Track track, {bool refresh = false}) async {
    if (!refresh) {
      final LyricsRow? cached = await _dao.getForTrack(track.id);
      if (cached != null) return _fromRow(cached);
    }

    for (final LyricsSourceResolver source in _sources) {
      RawLyrics? raw;
      try {
        raw = await source.resolve(track);
      } catch (_) {
        raw = null; // a flaky source never breaks the chain
      }
      if (raw == null) continue;
      final ParsedLrc parsed = LrcParser.parse(raw.text);
      if (parsed.isEmpty) continue;
      await _dao.upsert(
        trackId: track.id,
        source: raw.source,
        synced: parsed.isSynced,
        rawText: raw.text,
        parsedOk: true,
      );
      return Lyrics(
        lines: parsed.lines,
        isSynced: parsed.isSynced,
        source: raw.source,
      );
    }

    // Nothing found: write a negative-cache marker.
    await _dao.upsert(
      trackId: track.id,
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
    );
    return const Lyrics.none();
  }

  /// Drops any cache for [track] and re-resolves from scratch.
  Future<Lyrics> refresh(Track track) async {
    await _dao.deleteForTrack(track.id);
    return lyricsFor(track, refresh: true);
  }

  Lyrics _fromRow(LyricsRow row) {
    if (row.source == LyricsSource.none) return const Lyrics.none();
    final ParsedLrc parsed = LrcParser.parse(row.rawText);
    if (parsed.isEmpty) return const Lyrics.none();
    return Lyrics(
      lines: parsed.lines,
      isSynced: parsed.isSynced,
      source: row.source,
    );
  }
}
