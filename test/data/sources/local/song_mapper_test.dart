import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/song_mapper.dart';

/// Builds a fake [SongModel] from a MediaStore-shaped map (SongModel reads its
/// fields straight out of the map, so this exercises the real getters).
SongModel _song({
  required int id,
  String title = 'Title',
  String data = '/storage/emulated/0/Music/song.mp3',
  int? albumId = 10,
  String? album = 'Album',
  int? artistId = 20,
  String? artist = 'Artist',
  int? duration = 200000,
  int? dateAdded = 1000,
  int? dateModified = 2000,
  int? track,
  String? genre,
}) {
  return SongModel(<dynamic, dynamic>{
    '_id': id,
    'title': title,
    '_data': data,
    'album_id': albumId,
    'album': album,
    'artist_id': artistId,
    'artist': artist,
    'duration': duration,
    'date_added': dateAdded,
    'date_modified': dateModified,
    'track': track,
    'genre': genre,
  });
}

void main() {
  group('deterministic ids', () {
    test('track/album/artist ids follow the CLAUDE.md scheme', () {
      expect(localTrackId(5), 'local:5');
      expect(localAlbumId(10), 'local:album:10');
      expect(localArtistId(20), 'local:artist:20');
    });

    test('maps a song to a track companion with derived ids', () {
      final TracksCompanion c = songToTrackCompanion(
        _song(id: 5, albumId: 10, artistId: 20),
      );
      expect(c.id.value, 'local:5');
      expect(c.albumId.value, 'local:album:10');
      expect(c.artistId.value, 'local:artist:20');
      expect(c.source.value, TrackSource.local);
      expect(c.durationMs.value, 200000);
      expect(c.filePath.value, '/storage/emulated/0/Music/song.mp3');
    });

    test('falls back to a name-based album id when album_id is null', () {
      expect(
        albumIdForSong(_song(id: 1, albumId: null, album: 'Weird Tag')),
        'local:album:name:weird tag',
      );
      expect(
        artistIdForSong(_song(id: 1, artistId: null, artist: 'No ID Artist')),
        'local:artist:name:no id artist',
      );
    });

    test('splits MediaStore disc*1000+track encoding', () {
      expect(splitTrackNumber(1005), (discNo: 1, trackNo: 5));
      expect(splitTrackNumber(7), (discNo: 0, trackNo: 7));
      expect(splitTrackNumber(null), (discNo: 0, trackNo: 0));
    });
  });

  group('junk filtering', () {
    test('keeps a normal music file', () {
      expect(isJunkSong(_song(id: 1)), isFalse);
      expect(songToTrackCompanionOrNull(_song(id: 1)), isNotNull);
    });

    test('drops tracks under the minimum duration', () {
      expect(isJunkSong(_song(id: 1, duration: 3000)), isTrue);
      expect(songToTrackCompanionOrNull(_song(id: 1, duration: 3000)), isNull);
    });

    test('drops ringtones/notifications/alarms and app-private media', () {
      const List<String> junkPaths = <String>[
        '/storage/emulated/0/Ringtones/ring.ogg',
        '/storage/emulated/0/Notifications/ping.ogg',
        '/storage/emulated/0/Alarms/wake.ogg',
        '/storage/emulated/0/Android/media/com.app/cache.mp3',
      ];
      for (final String path in junkPaths) {
        expect(
          isJunkSong(_song(id: 1, data: path)),
          isTrue,
          reason: path,
        );
      }
    });

    test('duration filter is configurable', () {
      expect(
        isJunkSong(_song(id: 1, duration: 3000), minDurationMs: 1000),
        isFalse,
      );
    });
  });
}
