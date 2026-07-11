import '../db/daos/lyrics_dao.dart';
import '../db/viby_database.dart' show LyricsRow;
import '../models/track.dart';
import 'lrc_parser.dart';
import 'lyrics.dart';

/// How long a `none` row from an *online* miss is trusted before we retry (the
/// community may add lyrics later).
const Duration kNegativeCacheTtl = Duration(days: 14);

/// Raw (unparsed) lyrics fetched by a [LyricsSourceResolver], plus where they
/// came from. The repository parses [text] with [LrcParser]; a synced embedded
/// SYLT frame is serialized to LRC text upstream so parsing is uniform.
///
/// [instrumental] marks a confirmed-instrumental track (LRCLIB's flag): [text]
/// is empty and the repository caches it as [LyricsSource.instrumental].
class RawLyrics {
  const RawLyrics({
    required this.text,
    required this.source,
    this.instrumental = false,
  });

  const RawLyrics.instrumental()
      : text = '',
        source = LyricsSource.instrumental,
        instrumental = true;

  final String text;
  final LyricsSource source;
  final bool instrumental;
}

/// One link in the resolution chain.
///
/// Contract: return a [RawLyrics] on a hit; return **null** when this source
/// *definitively* has nothing (a cacheable miss); **throw** when it could not
/// determine an answer (offline / rate-limited / disabled) — a transient
/// "abstain" the repository must not persist as a negative cache.
abstract interface class LyricsSourceResolver {
  Future<RawLyrics?> resolve(Track track);
}

/// Resolves, parses, and caches lyrics per track — the one place every
/// provenance (sidecar / embedded / online) is turned into the single
/// [Lyrics] representation.
///
/// Priority is the order of [sources] (sidecar `.lrc` → embedded synced →
/// embedded unsynced → online); the first hit wins and is cached permanently in
/// drift. A **definitive** miss (no source threw) caches a [LyricsSource.none]
/// marker — with a [kNegativeCacheTtl] TTL if any source could have found online
/// lyrics — so we don't re-resolve every play. A miss where a source **threw**
/// (offline / gated) is *not* cached, so it retries later. Concurrent resolves
/// for the same track are de-duplicated (one network fetch ever, per play
/// session). Cached rows store raw text and are re-parsed on read.
class LyricsRepository {
  LyricsRepository({
    required LyricsDao dao,
    required List<LyricsSourceResolver> sources,
  })  : _dao = dao,
        _sources = sources;

  final LyricsDao _dao;
  final List<LyricsSourceResolver> _sources;

  /// In-flight resolutions, keyed by trackId (concurrent-fetch guard).
  final Map<String, Future<Lyrics>> _inflight = <String, Future<Lyrics>>{};

  /// Lyrics for [track], from cache when present and fresh. Pass [refresh] to
  /// bypass the cache and re-resolve.
  Future<Lyrics> lyricsFor(Track track, {bool refresh = false}) {
    if (refresh) return _resolve(track, useCache: false);
    final Future<Lyrics>? inflight = _inflight[track.id];
    if (inflight != null) return inflight;
    final Future<Lyrics> future = _resolve(track, useCache: true);
    _inflight[track.id] = future;
    return future.whenComplete(() => _inflight.remove(track.id));
  }

  Future<Lyrics> _resolve(Track track, {required bool useCache}) async {
    if (useCache) {
      final LyricsRow? cached = await _dao.getForTrack(track.id);
      if (cached != null && !_isStale(cached)) return _fromRow(cached);
    }

    bool abstained = false;
    for (final LyricsSourceResolver source in _sources) {
      RawLyrics? raw;
      try {
        raw = await source.resolve(track);
      } catch (_) {
        // A source that couldn't determine an answer (offline / gated / flaky).
        // Never fatal; remember it so we don't persist a false negative cache.
        abstained = true;
        continue;
      }
      if (raw == null) continue;

      if (raw.instrumental) {
        await _dao.upsert(
          trackId: track.id,
          source: LyricsSource.instrumental,
          synced: false,
          rawText: '',
          parsedOk: true,
        );
        return const Lyrics.instrumental();
      }

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

    // A source abstained (offline / gated): return empty transiently but do NOT
    // persist a negative cache, so it retries next time.
    if (abstained) return const Lyrics.none();

    // Definitive miss: negative cache with a TTL (an online source may find it
    // later once the community adds it).
    await _dao.upsert(
      trackId: track.id,
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
      expiresAt: DateTime.now().add(kNegativeCacheTtl),
    );
    return const Lyrics.none();
  }

  /// Drops any cache for [track] and re-resolves from scratch.
  Future<Lyrics> refresh(Track track) async {
    await _dao.deleteForTrack(track.id);
    return lyricsFor(track, refresh: true);
  }

  /// Caches a caller-supplied result (the manual "Search online" escape hatch),
  /// overriding whatever was there. Parses + upserts like the auto path.
  Future<Lyrics> cacheRaw(Track track, RawLyrics raw) async {
    if (raw.instrumental) {
      await _dao.upsert(
        trackId: track.id,
        source: LyricsSource.instrumental,
        synced: false,
        rawText: '',
        parsedOk: true,
      );
      return const Lyrics.instrumental();
    }
    final ParsedLrc parsed = LrcParser.parse(raw.text);
    if (parsed.isEmpty) return const Lyrics.none();
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

  /// A `none` row is stale once its online-miss TTL has passed; positive results
  /// (and TTL-less local misses) never expire.
  bool _isStale(LyricsRow row) =>
      row.source == LyricsSource.none &&
      row.expiresAt != null &&
      DateTime.now().isAfter(row.expiresAt!);

  Lyrics _fromRow(LyricsRow row) {
    switch (row.source) {
      case LyricsSource.none:
        return const Lyrics.none();
      case LyricsSource.instrumental:
        return const Lyrics.instrumental();
      case LyricsSource.sidecarLrc:
      case LyricsSource.embeddedSynced:
      case LyricsSource.embeddedUnsynced:
      case LyricsSource.online:
        final ParsedLrc parsed = LrcParser.parse(row.rawText);
        if (parsed.isEmpty) return const Lyrics.none();
        return Lyrics(
          lines: parsed.lines,
          isSynced: parsed.isSynced,
          source: row.source,
        );
    }
  }
}
