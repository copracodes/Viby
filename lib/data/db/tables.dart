import 'package:drift/drift.dart';

/// Where a [Tracks] row (and its album/artist) originated.
///
/// Stored as the enum *name* (`textEnum`) so reordering the enum can never
/// silently repoint existing rows.
enum TrackSource { local, subsonic }

/// Lifecycle of an offline copy in [CacheEntries].
enum CacheState { queued, downloading, complete, error }

/// Queue repeat behaviour persisted in [QueueState].
enum RepeatMode { off, one, all }

/// Library tracks — the heart of the schema.
///
/// `id` is a deterministic string (`local:<mediaStoreId>` /
/// `subsonic:<serverId>:<remoteId>`) so rescans upsert idempotently. `albumId`
/// and `artistId` are the matching deterministic ids; they are plain string
/// keys (not enforced FKs) because the scanner may write a track before its
/// album/artist row in a rescan and we resolve joins by id.
@DataClassName('TrackRow')
@TableIndex(name: 'idx_tracks_album', columns: {#albumId})
@TableIndex(name: 'idx_tracks_artist', columns: {#artistId})
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get source => textEnum<TrackSource>()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get title => text()();
  TextColumn get albumId => text()();
  TextColumn get artistId => text()();
  IntColumn get trackNo => integer().withDefault(const Constant(0))();
  IntColumn get discNo => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().nullable()();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get dateModified => dateTime()();
  TextColumn get artworkKey => text().nullable()();

  /// Whether this track is known-playable (added in schema v3). Set false when
  /// the player fails to load/decode the file (missing / corrupt); a rescan
  /// upserts it back to true. Playback skips over unplayable tracks so a rotten
  /// file can't stall the queue.
  BoolColumn get playable => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Albums, keyed by deterministic id (`local:<id>` / `subsonic:<sid>:<id>`).
@DataClassName('AlbumRow')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get artistId => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get artworkKey => text().nullable()();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Artists, keyed by deterministic id.
@DataClassName('ArtistRow')
class Artists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-created playlists. `id` is minted by the DAO (not source-derived).
@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get dateCreated => dateTime()();
  DateTimeColumn get dateModified => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered membership of tracks in a playlist.
///
/// A surrogate autoincrement `id` is the PK (not `position`) so reorders can
/// rewrite positions without transient unique-constraint clashes, and so a
/// track may appear more than once. `position` is kept dense (0..n-1) by the
/// DAO. Deleting the playlist cascades these away; `trackId` is a plain key so
/// pruning a track just leaves the join to drop it (no gap-inducing cascade).
@DataClassName('PlaylistEntryRow')
@TableIndex(name: 'idx_pe_playlist_pos', columns: {#playlistId, #position})
class PlaylistEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get playlistId =>
      text().references(Playlists, #id, onDelete: KeyAction.cascade)();
  TextColumn get trackId => text()();
  IntColumn get position => integer()();
}

/// Append-only play log. Deleting a track cascades its history away.
@DataClassName('PlayHistoryRow')
@TableIndex(name: 'idx_history_playedat', columns: {#playedAt})
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

/// Subsonic servers. Passwords are NEVER stored here — they live in
/// flutter_secure_storage keyed by this row's `id`.
@DataClassName('ServerRow')
class Servers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get username => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Offline cache bookkeeping, one row per track. Deleting a track cascades its
/// cache entry away (the file itself is removed by the cache manager).
@DataClassName('CacheEntryRow')
class CacheEntries extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text()();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  TextColumn get state => textEnum<CacheState>()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastAccessed => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Recent search terms (added in schema v2). One row per distinct query
/// (the query text is the primary key); [lastUsed] is bumped on re-search so
/// the DAO can surface the newest terms and prune the rest.
@DataClassName('SearchRow')
class Searches extends Table {
  TextColumn get query => text()();
  DateTimeColumn get lastUsed => dateTime()();

  @override
  Set<Column> get primaryKey => {query};
}

/// Cached dominant seed colour per artwork (added in schema v4) so album-art
/// dynamic theming is instant on cold start instead of re-running palette
/// extraction. [seedColor] is a packed ARGB int; keyed by the album's logical
/// [Tracks.artworkKey].
@DataClassName('ArtworkPaletteRow')
class ArtworkPalettes extends Table {
  TextColumn get artworkKey => text()();
  IntColumn get seedColor => integer()();

  @override
  Set<Column> get primaryKey => {artworkKey};
}

/// Generic key→value app preferences (added in schema v4): theme mode and the
/// dynamic-colour toggle live here, so a single small table covers app settings
/// without a migration per new preference.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Single-row table (id is pinned to 0) holding the restorable play queue.
@DataClassName('QueueStateRow')
class QueueState extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// JSON-encoded `List<String>` of track ids (serialised by [QueueDao]).
  TextColumn get trackIds => text()();
  IntColumn get currentIndex => integer().withDefault(const Constant(0))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  BoolColumn get shuffleOn => boolean().withDefault(const Constant(false))();
  TextColumn get repeatMode => textEnum<RepeatMode>()();

  @override
  Set<Column> get primaryKey => {id};
}
