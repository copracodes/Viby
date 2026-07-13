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

/// Where a track's cached [LyricsLines] came from (added in schema v7;
/// `online`/`instrumental` added in schema v8).
///
/// Resolution priority (first hit wins): `sidecarLrc` (a `.lrc` next to the
/// audio file or under a `/Lyrics/` folder) → `embeddedSynced` (an ID3 SYLT
/// frame, rare) → `embeddedUnsynced` (ID3 USLT / Vorbis LYRICS comment, static
/// display) → `online` (fetched from LRCLIB) → `none` (a negative-cache marker
/// so we don't re-resolve every play; a `none` row from an online miss carries
/// an [LyricsLines.expiresAt] TTL). `instrumental` is a *positive* result (the
/// track has no words) cached permanently. Stored as the enum *name*.
enum LyricsSource {
  sidecarLrc,
  embeddedSynced,
  embeddedUnsynced,
  online,
  instrumental,
  none,
}

/// Whether a [Tracks] row is shown in the library (added in schema v6).
///
/// Stored as the enum *name* (`textEnum`). `visible` is the default; junk
/// filtering marks recordings/voice-notes `hiddenByFilter` (stored, not dropped,
/// so a false positive is recoverable), and the track long-press "Hide song"
/// action marks a row `hiddenByUser`. Every library/search/playlist/queue read
/// filters to `visible`; the Hidden-songs screen reads the two hidden buckets.
enum TrackVisibility { visible, hiddenByUser, hiddenByFilter }

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

  /// Library visibility (added in schema v6). Defaults to `visible`; junk
  /// scoring sets `hiddenByFilter` and the user can set `hiddenByUser`. Every
  /// track read path filters to `visible` (see [TrackVisibility]).
  TextColumn get visibility => textEnum<TrackVisibility>()
      .withDefault(const Constant('visible'))();

  /// True once the user unhides an auto-hidden track (added in schema v6) — a
  /// permanent "this is real music" override so future scans never re-filter it.
  BoolColumn get userOverride =>
      boolean().withDefault(const Constant(false))();

  /// Whether the user has liked this track (added in schema v6). Drives the
  /// virtual "Liked Songs" collection.
  BoolColumn get liked => boolean().withDefault(const Constant(false))();

  /// When the track was liked (added in schema v6); null when not liked. Liked
  /// Songs is ordered by this, newest first.
  DateTimeColumn get likedAt => dateTime().nullable()();

  /// ReplayGain tags read off the file (added in schema v9). Gains are dB
  /// relative to the ReplayGain reference; peaks are sample peaks as a fraction
  /// of full scale (1.0 = 0 dBFS) and are what let volume normalization avoid
  /// clipping. All null on an untagged file — which is *kept distinct* from
  /// "not looked at yet" by [rgScanned], so untagged files aren't re-read from
  /// disk on every scan. The scanner never writes these columns in its normal
  /// upsert (they're absent from the companion), so a rescan preserves them;
  /// a *changed* file resets [rgScanned] and they're re-read.
  RealColumn get rgTrackGainDb => real().nullable()();
  RealColumn get rgTrackPeak => real().nullable()();
  RealColumn get rgAlbumGainDb => real().nullable()();
  RealColumn get rgAlbumPeak => real().nullable()();

  /// Whether the file has been examined for ReplayGain tags (added in v9).
  BoolColumn get rgScanned => boolean().withDefault(const Constant(false))();

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

/// Single-row (id pinned to 0) equalizer settings (added in schema v5).
///
/// Band gains are stored as a JSON map keyed by **center frequency in hertz**
/// (`{"60":3.5,"230":1.0,…}`), not by band index, so the saved curve survives a
/// device whose equalizer reports a different band count/layout — the
/// [EqDao]/service re-normalizes onto whatever bands the platform exposes.
/// Passwords-style secrets aren't involved; this is plain preference data.
@DataClassName('EqSettingsRow')
class EqSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// Master EQ switch. When false the equalizer + loudness effects are bypassed.
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  /// Loudness-enhancer target gain in decibels (0 = off).
  RealColumn get loudnessGain => real().withDefault(const Constant(0.0))();

  /// Id of the active preset — a built-in slug (`flat`, `rock`, …) or a custom
  /// `custom:<micros>-<rand>` id. Null once the user edits into a bespoke curve
  /// with no backing preset.
  TextColumn get activePresetId => text().nullable()();

  /// JSON `{centerFreqHz: gainDb}` of the current band gains (see class doc).
  TextColumn get bandGainsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-saved custom equalizer presets (added in schema v5). Built-in presets
/// are code (see `audio/eq_preset.dart`), not rows — only user curves live here.
/// `id` is DAO-minted (`custom:<micros>-<rand>`); [gainsJson] is the same
/// frequency-keyed map shape as [EqSettings.bandGainsJson].
@DataClassName('EqPresetRow')
class EqPresets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get gainsJson => text()();
  DateTimeColumn get dateCreated => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached resolved lyrics, one row per track (added in schema v7). Deleting a
/// track cascades its lyrics away; the incremental scanner also deletes the row
/// when a track's `dateModified` changes so lyrics re-resolve on next play.
///
/// [rawText] is the original document (LRC / plain), re-parsed on read by
/// `LrcParser` so the parser can evolve without a migration; [synced] /
/// [parsedOk] are denormalized flags for cheap "has synced lyrics" checks
/// without parsing. A [LyricsSource.none] row is a negative cache (no lyrics
/// found) — cleared by "Refresh lyrics" or a rescan.
@DataClassName('LyricsRow')
class LyricsLines extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get source => textEnum<LyricsSource>()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get rawText => text().withDefault(const Constant(''))();
  BoolColumn get parsedOk => boolean().withDefault(const Constant(false))();
  DateTimeColumn get resolvedAt => dateTime()();

  /// Negative-cache expiry (added in schema v8): set only on a `none` row that
  /// came from an *online* miss (now + 14 days), so a song the community may add
  /// later is retried after the TTL. Null = permanent (positive results, and
  /// local-only misses cleared explicitly on toggle/grant/rescan).
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {trackId};
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
