import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/sources/local/junk_filter.dart';

/// Builds [JunkSignals] with music-file defaults; override to probe a signal.
JunkSignals _sig({
  String path = '/storage/emulated/0/Music/song.mp3',
  String fileNameNoExt = 'song',
  String fileExtension = 'mp3',
  int durationMs = 210000,
  String? title = 'A Real Song',
  String? artist = 'A Real Artist',
  String? album = 'A Real Album',
  bool? isMusic,
  bool? isRingtone,
  bool? isNotification,
  bool? isAlarm,
}) {
  return JunkSignals(
    path: path,
    fileNameNoExt: fileNameNoExt,
    fileExtension: fileExtension,
    durationMs: durationMs,
    title: title,
    artist: artist,
    album: album,
    isMusic: isMusic,
    isRingtone: isRingtone,
    isNotification: isNotification,
    isAlarm: isAlarm,
  );
}

void main() {
  group('scoreJunk — recordings are caught', () {
    test('untagged voicemail under /Voicemail/ is hidden', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Voicemail/vm_001.amr',
        fileNameNoExt: 'vm_001',
        fileExtension: 'amr',
        durationMs: 12000,
        title: 'vm_001',
        artist: null,
        album: null,
      );
      expect(isFilterHidden(s), isTrue);
    });

    test('untagged voice note in /Voice Recorder/ is hidden', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Voice Recorder/REC_20260115.m4a',
        fileNameNoExt: 'REC_20260115',
        fileExtension: 'm4a',
        durationMs: 45000,
        title: 'REC_20260115',
        artist: null,
        album: null,
      );
      expect(isFilterHidden(s), isTrue);
    });

    test('MediaStore ringtone flag hides an untagged file', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Ringtones/tone.ogg',
        fileNameNoExt: 'tone',
        fileExtension: 'ogg',
        title: 'tone',
        artist: null,
        album: null,
        isRingtone: true,
      );
      expect(isFilterHidden(s), isTrue);
    });

    test('isMusic == false hides an untagged file', () {
      final JunkSignals s = _sig(
        fileNameNoExt: 'clip',
        title: 'clip', // MediaStore title defaults to the filename → untagged
        artist: null,
        album: null,
        isMusic: false,
      );
      expect(isFilterHidden(s), isTrue);
    });

    test('bare date-stamp filename with no tags is hidden', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Download/20260115_143022.m4a',
        fileNameNoExt: '20260115_143022',
        fileExtension: 'm4a',
        durationMs: 30000,
        title: '20260115_143022',
        artist: null,
        album: null,
      );
      expect(isFilterHidden(s), isTrue);
    });
  });

  group('scoreJunk — false-positive guards (legit music stays visible)', () {
    test('a 45s tagged interlude stays visible', () {
      // Short, but fully tagged (album interlude) → protected.
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Music/Album/03 Interlude.mp3',
        fileNameNoExt: '03 Interlude',
        durationMs: 45000,
        title: 'Interlude',
        artist: 'The Band',
        album: 'The Album',
      );
      expect(isFilterHidden(s), isFalse);
    });

    test('an untagged normal-length song in /Music/ stays visible', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Music/track01.mp3',
        fileNameNoExt: 'track01',
        durationMs: 200000,
        title: 'track01',
        artist: null,
        album: null,
      );
      expect(isFilterHidden(s), isFalse);
    });

    test('a tagged song inside a folder named Recordings stays visible', () {
      // Path segment "recordings" matches, but real tags protect it.
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Recordings/Live Set.mp3',
        fileNameNoExt: 'Live Set',
        durationMs: 240000,
        title: 'Live at the Club',
        artist: 'DJ Someone',
        album: 'Live Sessions',
      );
      expect(isFilterHidden(s), isFalse);
    });

    test('artist named "The Recordings" is not matched (segment, not substring)',
        () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Music/The Recordings/hit.mp3',
        fileNameNoExt: 'hit',
        title: 'Hit Single',
        artist: 'The Recordings',
        album: 'Debut',
      );
      expect(isFilterHidden(s), isFalse);
    });

    test('a song titled "Voice of the Heart" is not a recording', () {
      final JunkSignals s = _sig(
        path: '/storage/emulated/0/Music/voice_of_the_heart.mp3',
        fileNameNoExt: 'voice_of_the_heart',
        title: 'Voice of the Heart',
        artist: 'Carpenters',
        album: 'Voice of the Heart',
      );
      expect(isFilterHidden(s), isFalse);
    });
  });

  group('isTooShort — hard drop', () {
    test('under 5s is too short', () {
      expect(isTooShort(3000), isTrue);
      expect(isTooShort(5000), isFalse);
      expect(isTooShort(210000), isFalse);
    });
  });

  group('resolveVisibility — preserves user intent across rescans', () {
    TrackFlags flags(TrackVisibility v, {bool override = false}) => TrackFlags(
          visibility: v,
          userOverride: override,
          liked: false,
        );

    test('a new track takes the filter verdict', () {
      expect(
        resolveVisibility(existing: null, filterHidden: true),
        TrackVisibility.hiddenByFilter,
      );
      expect(
        resolveVisibility(existing: null, filterHidden: false),
        TrackVisibility.visible,
      );
    });

    test('a user override always wins (stays visible even if filter says hide)',
        () {
      expect(
        resolveVisibility(
          existing: flags(TrackVisibility.visible, override: true),
          filterHidden: true,
        ),
        TrackVisibility.visible,
      );
    });

    test('a user-hidden track stays hidden regardless of the filter', () {
      expect(
        resolveVisibility(
          existing: flags(TrackVisibility.hiddenByUser),
          filterHidden: false,
        ),
        TrackVisibility.hiddenByUser,
      );
    });

    test('a previously filter-hidden track can become visible when tags improve',
        () {
      expect(
        resolveVisibility(
          existing: flags(TrackVisibility.hiddenByFilter),
          filterHidden: false,
        ),
        TrackVisibility.visible,
      );
    });

    test('a previously visible track can move into hiddenByFilter', () {
      expect(
        resolveVisibility(
          existing: flags(TrackVisibility.visible),
          filterHidden: true,
        ),
        TrackVisibility.hiddenByFilter,
      );
    });
  });
}
