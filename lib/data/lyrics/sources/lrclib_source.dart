import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../db/tables.dart' show LyricsSource;
import '../../models/track.dart';
import '../lyrics_repository.dart';
import '../network_probe.dart';
import '../query_cleanup.dart';

/// One LRCLIB record (from `/api/get` or a `/api/search` candidate).
class LrclibRecord {
  const LrclibRecord({
    required this.trackName,
    required this.artistName,
    required this.durationSec,
    required this.instrumental,
    this.albumName,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LrclibRecord.fromJson(Map<String, dynamic> json) {
    final Object? dur = json['duration'];
    return LrclibRecord(
      trackName: (json['trackName'] as String?) ?? '',
      artistName: (json['artistName'] as String?) ?? '',
      albumName: json['albumName'] as String?,
      durationSec: dur is num ? dur.round() : 0,
      instrumental: json['instrumental'] == true,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
    );
  }

  final String trackName;
  final String artistName;
  final String? albumName;
  final int durationSec;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
}

/// The LRCLIB HTTP surface. Contract mirrors the repository's abstain/miss rule:
/// [get] returns null on a 404 (definitive not-found → try search); any
/// transport error (offline / timeout) **throws** (→ abstain, not a cached miss).
abstract interface class LrclibApi {
  Future<LrclibRecord?> get({
    required String track,
    required String artist,
    String? album,
    required int durationSec,
  });

  Future<List<LrclibRecord>> search({
    required String track,
    required String artist,
  });
}

/// Online lyrics via LRCLIB (`https://lrclib.net`) — the final link in the
/// resolution chain. Offline-first: everything it returns is cached permanently
/// by the repository; any transport failure throws so the repository abstains
/// (never a user-facing error, never a persisted false negative).
///
/// Exact match first (`/api/get`, duration is the accuracy weapon), then a
/// `/api/search` fallback scored by [pickBestCandidate] (duration proximity +
/// title/artist match; no confident candidate = miss, because wrong lyrics are
/// worse than none).
class LrclibSource implements LyricsSourceResolver {
  const LrclibSource({
    required LrclibApi api,
    required NetworkProbe networkProbe,
    required bool wifiOnly,
  })  : _api = api,
        _probe = networkProbe,
        _wifiOnly = wifiOnly;

  final LrclibApi _api;
  final NetworkProbe _probe;
  final bool _wifiOnly;

  @override
  Future<RawLyrics?> resolve(Track track) async {
    final LyricsQuery q = cleanLyricsQuery(
      title: track.title,
      artist: track.artistName ?? '',
      album: track.albumName,
    );
    if (!q.isUsable) return null; // no artist/title → nothing to look up

    if (_wifiOnly && !await _probe.isUnmetered()) {
      // Gated by the Wi-Fi-only setting: abstain (don't cache a false miss).
      throw const _AbstainException('wifi-only: metered network');
    }

    final int durationSec = track.durationMs ~/ 1000;

    // 1. Exact match.
    final LrclibRecord? exact = await _api.get(
      track: q.track,
      artist: q.artist,
      album: q.album,
      durationSec: durationSec,
    );
    if (exact != null) {
      final RawLyrics? raw = recordToRaw(exact);
      if (raw != null) return raw;
    }

    // 2. Search fallback, scored.
    final List<LrclibRecord> candidates =
        await _api.search(track: q.track, artist: q.artist);
    final LrclibRecord? best = pickBestCandidate(
      candidates,
      targetDurationSec: durationSec,
      cleanedTitle: q.track,
      cleanedArtist: q.artist,
    );
    if (best == null) return null; // no confident match → miss
    return recordToRaw(best);
  }

  /// Turns a record into [RawLyrics]: synced preferred, plain fallback,
  /// instrumental flag honoured; a record with no usable lyrics → null. Public
  /// so the manual "Search online" flow can apply a user-chosen candidate.
  static RawLyrics? recordToRaw(LrclibRecord r) {
    if (r.instrumental) return const RawLyrics.instrumental();
    final String? synced = r.syncedLyrics;
    if (synced != null && synced.trim().isNotEmpty) {
      return RawLyrics(text: synced, source: LyricsSource.online);
    }
    final String? plain = r.plainLyrics;
    if (plain != null && plain.trim().isNotEmpty) {
      return RawLyrics(text: plain, source: LyricsSource.online);
    }
    return null;
  }
}

/// Chooses the best search candidate: within [durationToleranceSec] of the
/// target duration AND a normalized title match; among those, the smallest
/// duration delta wins (tie-break: exact title, then artist match). Returns null
/// when nothing qualifies — ambiguity is rejected (wrong lyrics > no lyrics).
LrclibRecord? pickBestCandidate(
  List<LrclibRecord> candidates, {
  required int targetDurationSec,
  required String cleanedTitle,
  required String cleanedArtist,
  int durationToleranceSec = 3,
}) {
  final String wantTitle = _norm(cleanedTitle);
  final String wantArtist = _norm(cleanedArtist);
  if (wantTitle.isEmpty) return null;

  LrclibRecord? best;
  int bestDelta = 1 << 30;
  for (final LrclibRecord c in candidates) {
    final int delta = (c.durationSec - targetDurationSec).abs();
    if (delta > durationToleranceSec) continue;
    final String candTitle = _norm(c.trackName);
    if (candTitle != wantTitle) continue; // strict title match — avoid mismatches
    // Artist must be present in the candidate's (possibly multi-)artist field.
    if (wantArtist.isNotEmpty && !_norm(c.artistName).contains(wantArtist)) {
      continue;
    }
    if (delta < bestDelta) {
      best = c;
      bestDelta = delta;
    }
  }
  return best;
}

/// Normalizes for comparison: lowercase, alphanumeric only, collapsed. Keeps
/// non-ASCII letters (Arabic) so `أغنية` matches across sources.
String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '')
    .trim();

/// A transport-level abstain (distinct from a definitive miss). Any exception
/// thrown from [LrclibSource.resolve] is treated as abstain by the repository;
/// this named type just makes intent clear.
class _AbstainException implements Exception {
  const _AbstainException(this.message);
  final String message;
  @override
  String toString() => 'LrclibAbstain: $message';
}

/// The real [LrclibApi] over `dio`. Timeout 8s, no extra retries, a proper
/// User-Agent (LRCLIB asks clients to identify themselves — resolved lazily from
/// package info and cached). A 404 → null; any other error propagates (→ abstain).
class DioLrclibApi implements LrclibApi {
  DioLrclibApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://lrclib.net',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              responseType: ResponseType.json,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
        options.headers['User-Agent'] = await _userAgent();
        handler.next(options);
      },
    ));
  }

  final Dio _dio;

  static String? _cachedUa;

  static Future<String> _userAgent() async {
    if (_cachedUa != null) return _cachedUa!;
    const String contact = 'https://github.com/copra/viby';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _cachedUa = 'Viby/${info.version}+${info.buildNumber} ($contact)';
    } catch (_) {
      _cachedUa = 'Viby ($contact)';
    }
    return _cachedUa!;
  }

  @override
  Future<LrclibRecord?> get({
    required String track,
    required String artist,
    String? album,
    required int durationSec,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/get',
        queryParameters: <String, dynamic>{
          'track_name': track,
          'artist_name': artist,
          if (album != null && album.isNotEmpty) 'album_name': album,
          'duration': durationSec,
        },
      );
      final Object? data = resp.data;
      if (data is Map<String, dynamic>) return LrclibRecord.fromJson(data);
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null; // not found → try search
      rethrow; // transport error → abstain
    }
  }

  @override
  Future<List<LrclibRecord>> search({
    required String track,
    required String artist,
  }) async {
    final Response<dynamic> resp = await _dio.get<dynamic>(
      '/api/search',
      queryParameters: <String, dynamic>{
        'track_name': track,
        'artist_name': artist,
      },
    );
    final Object? data = resp.data;
    if (data is! List) return const <LrclibRecord>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(LrclibRecord.fromJson)
        .toList();
  }
}
