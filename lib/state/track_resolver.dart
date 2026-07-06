import '../data/db/daos/library_dao.dart' show TrackWithMeta;
import '../data/models/track.dart';
import '../data/sources/local/artwork_service.dart';

/// Turns DB rows (+ joined album/artist names) into playable domain [Track]s,
/// filling in the resolved on-disk artwork path so the player/notification can
/// render art without touching the artwork source.
///
/// Artwork lookups are deduped per `artworkKey` (tracks of the same album share
/// one), keeping this cheap even for whole-library queues.
Future<List<Track>> resolveTracks(
  List<TrackWithMeta> metas,
  ArtworkService artwork,
) async {
  final Map<String, String?> artByKey = <String, String?>{};
  final List<Track> out = <Track>[];
  for (final TrackWithMeta meta in metas) {
    final String? key = meta.track.artworkKey;
    String? path;
    if (key != null) {
      if (artByKey.containsKey(key)) {
        path = artByKey[key];
      } else {
        path = await artwork.resolvedPath(key);
        artByKey[key] = path;
      }
    }
    out.add(
      Track.fromRow(
        meta.track,
        albumName: meta.albumName,
        artistName: meta.artistName,
        artworkPath: path,
      ),
    );
  }
  return out;
}
