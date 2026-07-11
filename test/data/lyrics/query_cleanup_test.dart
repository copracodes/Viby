import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/query_cleanup.dart';

void main() {
  group('cleanTitle', () {
    // Real-world messy-title patterns → what LRCLIB should be queried with.
    const Map<String, String> cases = <String, String>{
      'Song (feat. Drake)': 'Song',
      'Song (ft. Drake)': 'Song',
      'Song [feat. Someone Else]': 'Song',
      'Song (with Anaïs)': 'Song',
      'Bohemian Rhapsody - Remastered 2011': 'Bohemian Rhapsody',
      'Wish You Were Here (2011 Remastered Version)': 'Wish You Were Here',
      'Hotel California - 2013 Remaster': 'Hotel California',
      'Someone Like You (Live)': 'Someone Like You',
      'Fix You (Live at Glastonbury)': 'Fix You',
      'Blinding Lights (Deluxe Edition)': 'Blinding Lights',
      'Levitating - Single': 'Levitating',
      'Lose Yourself - Radio Edit': 'Lose Yourself',
      'Clocks (Acoustic)': 'Clocks',
      'Yesterday feat. Someone': 'Yesterday',
      'Plain Title': 'Plain Title',
      'Multi   Space   Title': 'Multi Space Title',
    };

    cases.forEach((String input, String expected) {
      test('"$input" → "$expected"', () {
        expect(cleanTitle(input), expected);
      });
    });
  });

  group('primaryArtist', () {
    const Map<String, String> cases = <String, String>{
      'Drake': 'Drake',
      'Drake feat. Rihanna': 'Drake',
      'Drake ft. Rihanna': 'Drake',
      'Calvin Harris & Dua Lipa': 'Calvin Harris',
      'Eminem, Rihanna': 'Eminem',
      'Jay-Z / Kanye West': 'Jay-Z',
      'Rae Sremmurd x Gucci Mane': 'Rae Sremmurd',
      'David Guetta feat. Sia': 'David Guetta',
      '<unknown>': '',
      '': '',
    };

    cases.forEach((String input, String expected) {
      test('"$input" → "$expected"', () {
        expect(primaryArtist(input), expected);
      });
    });
  });

  group('cleanLyricsQuery', () {
    test('combines cleaned title + primary artist, drops unknown album', () {
      final LyricsQuery q = cleanLyricsQuery(
        title: 'Song (feat. Drake) - Remastered 2011',
        artist: 'Artist feat. Guest',
        album: '<unknown>',
      );
      expect(q.track, 'Song');
      expect(q.artist, 'Artist');
      expect(q.album, isNull);
      expect(q.isUsable, isTrue);
    });

    test('keeps a real album', () {
      final LyricsQuery q = cleanLyricsQuery(
        title: 'Track',
        artist: 'Artist',
        album: 'Greatest Hits',
      );
      expect(q.album, 'Greatest Hits');
    });

    test('an unknown artist makes the query unusable', () {
      final LyricsQuery q =
          cleanLyricsQuery(title: 'Track', artist: '<unknown>');
      expect(q.isUsable, isFalse);
    });
  });
}
