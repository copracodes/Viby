import 'package:drift/drift.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../db/tables.dart';
import '../../db/viby_database.dart';

/// Minimum track length; anything shorter is treated as junk (UI SFX, voice
/// memos, ringtone fragments). A constant so we can settle the value later.
const int kMinTrackDurationMs = 5000;

/// Path fragments (lower-cased) that mark a MediaStore entry as not-music:
/// ringtones/notifications/alarms and app-private media under Android/.
const List<String> kJunkPathFragments = <String>[
  '/ringtones/',
  '/notifications/',
  '/alarms/',
  '/android/media/',
  '/android/data/',
];

// --- Deterministic id helpers (see CLAUDE.md ID strategy) ------------------

String localTrackId(int mediaStoreId) => 'local:$mediaStoreId';
String localAlbumId(int albumId) => 'local:album:$albumId';
String localArtistId(int artistId) => 'local:artist:$artistId';

/// Album id for a song, falling back to a name-derived key when MediaStore has
/// no numeric album id (kept deterministic so rescans still upsert idempotently).
String albumIdForSong(SongModel song) {
  final int? id = song.albumId;
  if (id != null) return localAlbumId(id);
  final String name = (song.album ?? 'Unknown Album').trim().toLowerCase();
  return 'local:album:name:$name';
}

String artistIdForSong(SongModel song) {
  final int? id = song.artistId;
  if (id != null) return localArtistId(id);
  final String name = (song.artist ?? 'Unknown Artist').trim().toLowerCase();
  return 'local:artist:name:$name';
}

/// Whether a MediaStore song should be skipped (too short, or under a
/// ringtone/notification/app-private path).
bool isJunkSong(SongModel song, {int minDurationMs = kMinTrackDurationMs}) {
  if ((song.duration ?? 0) < minDurationMs) return true;
  final String path = song.data.toLowerCase();
  for (final String fragment in kJunkPathFragments) {
    if (path.contains(fragment)) return true;
  }
  return false;
}

DateTime _epochSecondsToDate(int? seconds) =>
    DateTime.fromMillisecondsSinceEpoch((seconds ?? 0) * 1000);

/// MediaStore encodes disc+track as `disc*1000 + track` (e.g. 1005 = disc 1,
/// track 5). Split it back out.
({int discNo, int trackNo}) splitTrackNumber(int? raw) {
  final int value = raw ?? 0;
  if (value > 1000) {
    return (discNo: value ~/ 1000, trackNo: value % 1000);
  }
  return (discNo: 0, trackNo: value);
}

/// Maps a MediaStore song to a track upsert row (artwork resolved later).
TracksCompanion songToTrackCompanion(SongModel song) {
  final ({int discNo, int trackNo}) numbers = splitTrackNumber(song.track);
  return TracksCompanion.insert(
    id: localTrackId(song.id),
    source: TrackSource.local,
    title: song.title,
    albumId: albumIdForSong(song),
    artistId: artistIdForSong(song),
    filePath: Value(song.data),
    trackNo: Value(numbers.trackNo),
    discNo: Value(numbers.discNo),
    durationMs: Value(song.duration ?? 0),
    genre: Value(song.genre),
    dateAdded: _epochSecondsToDate(song.dateAdded),
    dateModified: _epochSecondsToDate(song.dateModified),
  );
}

TracksCompanion? songToTrackCompanionOrNull(
  SongModel song, {
  int minDurationMs = kMinTrackDurationMs,
}) {
  if (isJunkSong(song, minDurationMs: minDurationMs)) return null;
  return songToTrackCompanion(song);
}

AlbumsCompanion songToAlbumCompanion(SongModel song) {
  return AlbumsCompanion.insert(
    id: albumIdForSong(song),
    name: song.album ?? 'Unknown Album',
    artistId: artistIdForSong(song),
  );
}

ArtistsCompanion songToArtistCompanion(SongModel song) {
  return ArtistsCompanion.insert(
    id: artistIdForSong(song),
    name: song.artist ?? 'Unknown Artist',
  );
}
