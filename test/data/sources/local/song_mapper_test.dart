import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/junk_filter.dart';
import 'package:viby/data/sources/local/song_mapper.dart';

/// Builds a fake [SongModel] from a MediaStore-shaped map (SongModel reads its
/// fields straight out of the map, so this exercises the real getters).
SongModel _song({
  required int id,
  String title = 'Title',
  String data = '/storage/emulated/0/Music/song.mp3',
  String displayNameWOExt = 'song',
  String fileExtension = 'mp3',
  int? albumId = 10,
  String? album = 'Album',
  int? artistId = 20,
  String? artist = 'Artist',
  int? duration = 200000,
  int? dateAdded = 1000,
  int? dateModified = 2000,
  int? track,
  String? genre,
  bool? isMusic,
  bool? isRingtone,
  bool? isNotification,
  bool? isAlarm,
}) {
  return SongModel(<dynamic, dynamic>{
    '_id': id,
    'title': title,
    '_data': data,
    '_display_name': '$displayNameWOExt.$fileExtension',
    '_display_name_wo_ext': displayNameWOExt,
    'file_extension': fileExtension,
    'album_id': albumId,
    'album': album,
    'artist_id': artistId,
    'artist': artist,
    'duration': duration,
    'date_added': dateAdded,
    'date_modified': dateModified,
    'track': track,
    'genre': genre,
    'is_music': isMusic,
    'is_ringtone': isRingtone,
    'is_notification': isNotification,
    'is_alarm': isAlarm,
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

  group('junkSignalsFromSong adapter', () {
    test('carries path, filename, extension, duration and type flags', () {
      final JunkSignals s = junkSignalsFromSong(_song(
        id: 1,
        data: '/storage/emulated/0/Recordings/VN_01.amr',
        displayNameWOExt: 'VN_01',
        fileExtension: 'amr',
        duration: 8000,
        title: 'VN_01',
        artist: null,
        album: null,
        isMusic: false,
      ));
      expect(s.path, '/storage/emulated/0/Recordings/VN_01.amr');
      expect(s.fileNameNoExt, 'VN_01');
      expect(s.fileExtension, 'amr');
      expect(s.durationMs, 8000);
      expect(s.isMusic, isFalse);
      // A recording under /Recordings/ with a recording extension, untagged →
      // stored hidden by the filter (not dropped).
      expect(isFilterHidden(s), isTrue);
    });

    test('a normal tagged music file is not filter-hidden', () {
      expect(isFilterHidden(junkSignalsFromSong(_song(id: 1))), isFalse);
    });

    test('companion defaults to visible, unliked, no override', () {
      final TracksCompanion c = songToTrackCompanion(_song(id: 5));
      expect(c.visibility.value, TrackVisibility.visible);
      expect(c.liked.value, isFalse);
      expect(c.userOverride.value, isFalse);
      expect(c.likedAt.value, isNull);
    });

    test('companion carries preserved flags when passed', () {
      final DateTime when = DateTime(2026, 3, 4);
      final TracksCompanion c = songToTrackCompanion(
        _song(id: 5),
        visibility: TrackVisibility.hiddenByUser,
        liked: true,
        likedAt: when,
        userOverride: true,
      );
      expect(c.visibility.value, TrackVisibility.hiddenByUser);
      expect(c.liked.value, isTrue);
      expect(c.likedAt.value, when);
      expect(c.userOverride.value, isTrue);
    });
  });
}
