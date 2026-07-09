import 'package:drift/drift.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../db/tables.dart';
import '../../db/viby_database.dart';
import 'junk_filter.dart';

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

/// Extracts the plugin-free [JunkSignals] the pure scorer needs from a
/// MediaStore [song] (filename without extension, extension, tags, type flags).
JunkSignals junkSignalsFromSong(SongModel song) {
  String ext = song.fileExtension.toLowerCase().trim();
  if (ext.startsWith('.')) ext = ext.substring(1);
  return JunkSignals(
    path: song.data,
    fileNameNoExt: song.displayNameWOExt,
    fileExtension: ext,
    durationMs: song.duration ?? 0,
    title: song.title,
    artist: song.artist,
    album: song.album,
    isMusic: song.isMusic,
    isRingtone: song.isRingtone,
    isNotification: song.isNotification,
    isAlarm: song.isAlarm,
  );
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
///
/// [visibility] is decided by the scanner via the pure junk scorer +
/// [resolveVisibility]; [liked]/[likedAt]/[userOverride] carry the values the
/// scanner preserved from any existing row (a rescan must never clobber a user's
/// like or hide/unhide choice).
TracksCompanion songToTrackCompanion(
  SongModel song, {
  TrackVisibility visibility = TrackVisibility.visible,
  bool userOverride = false,
  bool liked = false,
  DateTime? likedAt,
}) {
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
    visibility: Value(visibility),
    userOverride: Value(userOverride),
    liked: Value(liked),
    likedAt: Value(likedAt),
  );
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
