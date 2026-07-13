import '../../audio/replay_gain.dart' show ReplayGainInfo;
import '../db/tables.dart' show TrackSource;
import '../db/viby_database.dart' show TrackRow;

/// The one playable track model for the whole app (CLAUDE.md rule 2).
///
/// It branches on [source] rather than having per-source subclasses: a `local`
/// track plays from [filePath]; a `subsonic` track (Phase 2) will stream from a
/// URL derived from [remoteId]. Album/artist are carried both as deterministic
/// ids (for navigation) and as already-resolved display names (so the player /
/// notification never needs a second query).
///
/// [artworkPath] is the *resolved on-disk* path of the album art (or null),
/// filled in by the state layer from [artworkKey] via `ArtworkService`, so the
/// audio layer can hand a `file://` art URI to the OS media session without
/// depending on the artwork source.
class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    required this.albumId,
    required this.artistId,
    this.artistName,
    this.albumName,
    this.durationMs = 0,
    this.filePath,
    this.remoteId,
    this.artworkKey,
    this.artworkPath,
    this.replayGain,
  });

  /// Builds a domain [Track] from a drift [TrackRow], optionally enriched with
  /// resolved album/artist names and the on-disk artwork path.
  factory Track.fromRow(
    TrackRow row, {
    String? albumName,
    String? artistName,
    String? artworkPath,
  }) {
    return Track(
      id: row.id,
      source: row.source,
      title: row.title,
      albumId: row.albumId,
      artistId: row.artistId,
      artistName: artistName,
      albumName: albumName,
      durationMs: row.durationMs,
      filePath: row.filePath,
      remoteId: row.remoteId,
      artworkKey: row.artworkKey,
      artworkPath: artworkPath,
      replayGain: ReplayGainInfo(
        trackGainDb: row.rgTrackGainDb,
        trackPeak: row.rgTrackPeak,
        albumGainDb: row.rgAlbumGainDb,
        albumPeak: row.rgAlbumPeak,
      ),
    );
  }

  final String id;
  final TrackSource source;
  final String title;
  final String albumId;
  final String artistId;
  final String? artistName;
  final String? albumName;
  final int durationMs;

  /// On-device file path (local tracks only; null for subsonic).
  final String? filePath;

  /// Server-side id (subsonic tracks only; null for local).
  final String? remoteId;

  /// Logical artwork id (album's deterministic id); null if no art.
  final String? artworkKey;

  /// Resolved on-disk artwork file path; null if art isn't cached/known.
  final String? artworkPath;

  /// The track's ReplayGain tags, if the scanner read any. The audio layer turns
  /// these into a volume scalar (`audio/replay_gain.dart`); an untagged track
  /// carries an empty [ReplayGainInfo] and plays untouched.
  final ReplayGainInfo? replayGain;

  Duration get duration => Duration(milliseconds: durationMs);

  Track copyWith({String? artworkPath}) {
    return Track(
      id: id,
      source: source,
      title: title,
      albumId: albumId,
      artistId: artistId,
      artistName: artistName,
      albumName: albumName,
      durationMs: durationMs,
      filePath: filePath,
      remoteId: remoteId,
      artworkKey: artworkKey,
      artworkPath: artworkPath ?? this.artworkPath,
      replayGain: replayGain,
    );
  }

  /// Identity is the deterministic [id]: the same track added to the queue twice
  /// compares equal (queue ops that remove "the same track" drop one instance).
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Track && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, "$title")';
}
