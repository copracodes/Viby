// Smart junk filtering — a pure, table-driven scorer that decides whether a
// MediaStore entry is a recording / ringtone / voice-note rather than music.
//
// Design constraint: false positives are the enemy. The scorer never hard-drops
// (the scanner stores over-threshold tracks as TrackVisibility.hiddenByFilter so
// a mistake is recoverable), and any real tag is a strong protective signal so
// genuine music — even a short interlude, or a song that happens to live in a
// folder named "Recordings" — stays visible.
//
// Everything here is plugin-free and side-effect-free; JunkSignals is built from
// SongModel by a thin adapter in song_mapper.dart, so the scoring is exhaustively
// unit-testable without the platform.

import '../../db/tables.dart';

/// Minimum track length; anything shorter is a **hard drop** (UI blips, ringtone
/// fragments) — never stored, so it doesn't even reach the scorer.
const int kMinTrackDurationMs = 5000;

/// A track this short *with no real tags* is a strong recording signal (a memo,
/// a voicemail). Above this, short-ness alone means nothing.
const int kShortRecordingMs = 90000; // 90s

// --- Score weights (a signal at or above [kJunkThreshold] hides the track) ---

/// A signal strong enough that, on its own and untagged, it hides the track.
const int kJunkStrong = 3;

/// Real tags (artist/album/a title that isn't just the filename) pull the score
/// back down. One strong recording signal + real tags nets below threshold, so
/// tagged music stays visible; it takes *two* strong signals to overcome tags.
const int kTagProtection = -3;

/// Hide (as [TrackVisibility.hiddenByFilter]) at or above this score.
const int kJunkThreshold = 3;

/// Path *segments* (a whole `/`-delimited component, case-insensitive) that mark
/// a recording/ringtone location. Matched as segments — not substrings — so the
/// artist "The Recordings" or a song in `/Music/Alarms Anthology/` is safe only
/// because we compare the whole segment, not `contains`.
const List<String> kRecordingPathSegments = <String>[
  'recordings',
  'recording',
  'voice recorder',
  'voice recorders',
  'sound recorder',
  'call',
  'call recordings',
  'voicemail',
  'voicemails',
  'notification',
  'notifications',
  'ringtone',
  'ringtones',
  'alarm',
  'alarms',
  'whatsapp voice notes',
  'voice notes',
  'ptt',
];

/// File extensions that are almost exclusively recordings / telephony codecs.
const List<String> kRecordingExtensions = <String>['amr', '3gp', 'awb', 'qcp'];

/// The plugin-free inputs the scorer needs. Built from `SongModel` by the
/// adapter in `song_mapper.dart`.
class JunkSignals {
  const JunkSignals({
    required this.path,
    required this.fileNameNoExt,
    required this.fileExtension,
    required this.durationMs,
    this.title,
    this.artist,
    this.album,
    this.isMusic,
    this.isRingtone,
    this.isNotification,
    this.isAlarm,
  });

  final String path;
  final String fileNameNoExt;
  final String fileExtension; // lower-case, no dot
  final int durationMs;
  final String? title;
  final String? artist;
  final String? album;
  final bool? isMusic;
  final bool? isRingtone;
  final bool? isNotification;
  final bool? isAlarm;

  /// Whether the track carries a real, human-authored tag. A MediaStore `title`
  /// defaults to the filename when untagged, so a title only counts if it
  /// differs from the filename; artist/album count when present and not the
  /// literal `<unknown>` sentinel.
  bool get hasRealTags {
    bool real(String? v) {
      if (v == null) return false;
      final String t = v.trim();
      return t.isNotEmpty && t != '<unknown>';
    }

    final bool titleTag = real(title) && title!.trim() != fileNameNoExt.trim();
    return titleTag || real(artist) || real(album);
  }
}

/// Lower-cased path segments of [path] (handles both `/` and `\`).
List<String> _segments(String path) => path
    .toLowerCase()
    .split(RegExp(r'[\\/]+'))
    .where((String s) => s.isNotEmpty)
    .toList();

bool _hasRecordingSegment(String path) {
  final List<String> segs = _segments(path);
  // Drop the last segment (the filename) — segment rules are about folders.
  final Iterable<String> folders =
      segs.isEmpty ? const <String>[] : segs.take(segs.length - 1);
  for (final String seg in folders) {
    if (kRecordingPathSegments.contains(seg)) return true;
  }
  return false;
}

/// Filenames like `REC_0012`, `VN 3`, `PTT-1`, `Call_20260115`, `Voice 2`, or a
/// bare date-stamp `20260115_143022`. Deliberately narrow so "Voice of the
/// Heart" or "Call Me Maybe" never match.
final RegExp _recordingNamePattern = RegExp(
  r'^(rec|vn|ptt)[ _\-]?\d'
  r'|^call[ _\-]'
  r'|^voice[ _\-]?\d'
  r'|^\d{6,}[ _\-]?\d{0,6}$', // date-stamp-only
  caseSensitive: false,
);

bool _looksLikeRecordingName(String fileNameNoExt) =>
    _recordingNamePattern.hasMatch(fileNameNoExt.trim());

/// The junk score for [s]. Higher = more likely a recording. Pure.
int scoreJunk(JunkSignals s) {
  int score = 0;

  if (_hasRecordingSegment(s.path)) score += kJunkStrong;
  if (kRecordingExtensions.contains(s.fileExtension.toLowerCase())) {
    score += kJunkStrong;
  }

  // MediaStore type flags — explicit non-music / ringtone / notification / alarm.
  if (s.isMusic == false) score += kJunkStrong;
  if (s.isRingtone == true || s.isNotification == true || s.isAlarm == true) {
    score += kJunkStrong;
  }

  // Recording-style filename, but only when there's nothing tagged to protect.
  if (!s.hasRealTags && _looksLikeRecordingName(s.fileNameNoExt)) {
    score += kJunkStrong;
  }

  // Untagged AND short — the classic voicemail/memo shape.
  if (!s.hasRealTags && s.durationMs < kShortRecordingMs) {
    score += kJunkStrong;
  }

  // Real tags strongly protect genuine music (applied once).
  if (s.hasRealTags) score += kTagProtection;

  return score;
}

/// Whether [s] should be stored hidden ([TrackVisibility.hiddenByFilter]).
bool isFilterHidden(JunkSignals s) => scoreJunk(s) >= kJunkThreshold;

/// Whether a track this short must be hard-dropped (never stored).
bool isTooShort(int durationMs, {int minDurationMs = kMinTrackDurationMs}) =>
    durationMs < minDurationMs;

/// The persisted per-track flags a rescan must preserve.
class TrackFlags {
  const TrackFlags({
    required this.visibility,
    required this.userOverride,
    required this.liked,
    this.likedAt,
  });

  final TrackVisibility visibility;
  final bool userOverride;
  final bool liked;
  final DateTime? likedAt;
}

/// Decides a track's visibility on (re)scan, preserving user intent. Pure.
///
/// - New track ([existing] null): filter score decides.
/// - A user override ("this is real music") always wins → visible, forever.
/// - A user-hidden track stays hidden regardless of the filter.
/// - Otherwise the filter decides (a track can move in/out of hiddenByFilter as
///   its tags/location change between scans).
TrackVisibility resolveVisibility({
  required TrackFlags? existing,
  required bool filterHidden,
}) {
  if (existing == null) {
    return filterHidden
        ? TrackVisibility.hiddenByFilter
        : TrackVisibility.visible;
  }
  if (existing.userOverride) return TrackVisibility.visible;
  if (existing.visibility == TrackVisibility.hiddenByUser) {
    return TrackVisibility.hiddenByUser;
  }
  return filterHidden
      ? TrackVisibility.hiddenByFilter
      : TrackVisibility.visible;
}
