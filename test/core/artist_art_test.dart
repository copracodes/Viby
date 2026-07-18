import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/artist_art.dart';

ArtistArtCandidate _c(
  String id, {
  String? art,
  int plays = 0,
  int tracks = 0,
  String? name,
}) =>
    ArtistArtCandidate(
      albumId: id,
      name: name ?? id,
      artworkKey: art,
      trackCount: tracks,
      playCount: plays,
    );

void main() {
  group('pickArtistArtworkKey (portrait selection order)', () {
    test('most-played album wins', () {
      final String? key = pickArtistArtworkKey(<ArtistArtCandidate>[
        _c('quiet', art: 'k_quiet', plays: 3, tracks: 20),
        _c('hit', art: 'k_hit', plays: 40, tracks: 5),
      ]);
      expect(key, 'k_hit');
    });

    test('tie on plays → most tracks', () {
      final String? key = pickArtistArtworkKey(<ArtistArtCandidate>[
        _c('single', art: 'k_single', plays: 0, tracks: 1),
        _c('lp', art: 'k_lp', plays: 0, tracks: 12),
      ]);
      expect(key, 'k_lp');
    });

    test('tie on plays and tracks → first alphabetical', () {
      final String? key = pickArtistArtworkKey(<ArtistArtCandidate>[
        _c('z', art: 'k_z', name: 'Zebra', plays: 2, tracks: 10),
        _c('a', art: 'k_a', name: 'Apple', plays: 2, tracks: 10),
      ]);
      expect(key, 'k_a');
    });

    test('albums without art are ignored', () {
      final String? key = pickArtistArtworkKey(<ArtistArtCandidate>[
        _c('mostplayed', plays: 99, tracks: 10), // no art → skipped
        _c('withart', art: 'k_art', plays: 1, tracks: 1),
      ]);
      expect(key, 'k_art');
    });

    test('no album with art → null (letter fallback)', () {
      expect(
        pickArtistArtworkKey(<ArtistArtCandidate>[_c('a', plays: 5)]),
        isNull,
      );
      expect(pickArtistArtworkKey(<ArtistArtCandidate>[]), isNull);
    });
  });
}
