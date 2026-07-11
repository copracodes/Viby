import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/lyrics/lyrics_repository.dart';
import 'package:viby/data/lyrics/network_probe.dart';
import 'package:viby/data/lyrics/sources/lrclib_source.dart';
import 'package:viby/data/models/track.dart';

LrclibRecord _rec({
  String title = 'Song',
  String artist = 'Artist',
  int dur = 200,
  bool instrumental = false,
  String? synced,
  String? plain,
}) =>
    LrclibRecord(
      trackName: title,
      artistName: artist,
      durationSec: dur,
      instrumental: instrumental,
      syncedLyrics: synced,
      plainLyrics: plain,
    );

class _FakeApi implements LrclibApi {
  _FakeApi({
    this.getResult,
    this.searchResults = const <LrclibRecord>[],
    this.throwOnGet = false,
  });

  LrclibRecord? getResult;
  List<LrclibRecord> searchResults;
  bool throwOnGet;
  int getCalls = 0;
  int searchCalls = 0;

  @override
  Future<LrclibRecord?> get({
    required String track,
    required String artist,
    String? album,
    required int durationSec,
  }) async {
    getCalls++;
    if (throwOnGet) throw Exception('network');
    return getResult;
  }

  @override
  Future<List<LrclibRecord>> search({
    required String track,
    required String artist,
  }) async {
    searchCalls++;
    return searchResults;
  }
}

class _FakeProbe implements NetworkProbe {
  _FakeProbe(this.unmetered);
  final bool unmetered;
  @override
  Future<bool> isUnmetered() async => unmetered;
}

const Track _track = Track(
  id: 'local:1',
  source: TrackSource.local,
  title: 'Song',
  albumId: 'a',
  artistId: 'ar',
  artistName: 'Artist',
  albumName: 'Album',
  durationMs: 200000, // 200s
);

void main() {
  group('pickBestCandidate', () {
    test('picks a within-tolerance title+artist match, smallest delta', () {
      final List<LrclibRecord> cands = <LrclibRecord>[
        _rec(dur: 205), // 5s off → rejected
        _rec(dur: 202, synced: '[00:01.00]a'), // 2s off → candidate
        _rec(dur: 200, synced: '[00:01.00]b'), // 0s off → best
      ];
      final LrclibRecord? best = pickBestCandidate(cands,
          targetDurationSec: 200, cleanedTitle: 'Song', cleanedArtist: 'Artist');
      expect(best, isNotNull);
      expect(best!.durationSec, 200);
    });

    test('rejects when duration is outside tolerance', () {
      final LrclibRecord? best = pickBestCandidate(
        <LrclibRecord>[_rec(dur: 210)],
        targetDurationSec: 200,
        cleanedTitle: 'Song',
        cleanedArtist: 'Artist',
      );
      expect(best, isNull);
    });

    test('rejects a different title even at the same duration', () {
      final LrclibRecord? best = pickBestCandidate(
        <LrclibRecord>[_rec(title: 'Different Song', dur: 200)],
        targetDurationSec: 200,
        cleanedTitle: 'Song',
        cleanedArtist: 'Artist',
      );
      expect(best, isNull);
    });

    test('rejects a wrong artist (same title, same duration)', () {
      final LrclibRecord? best = pickBestCandidate(
        <LrclibRecord>[_rec(artist: 'Someone Else', dur: 200)],
        targetDurationSec: 200,
        cleanedTitle: 'Song',
        cleanedArtist: 'Artist',
      );
      expect(best, isNull);
    });

    test('title match ignores case/punctuation; artist may include features',
        () {
      final LrclibRecord? best = pickBestCandidate(
        <LrclibRecord>[_rec(title: 'SONG!', artist: 'Artist feat. X', dur: 201)],
        targetDurationSec: 200,
        cleanedTitle: 'Song',
        cleanedArtist: 'Artist',
      );
      expect(best, isNotNull);
    });

    test('empty candidate list → null', () {
      expect(
        pickBestCandidate(const <LrclibRecord>[],
            targetDurationSec: 200,
            cleanedTitle: 'Song',
            cleanedArtist: 'Artist'),
        isNull,
      );
    });
  });

  group('LrclibSource.resolve', () {
    LrclibSource source(_FakeApi api,
            {bool wifiOnly = false, bool unmetered = true}) =>
        LrclibSource(
            api: api, networkProbe: _FakeProbe(unmetered), wifiOnly: wifiOnly);

    test('exact match returns synced online lyrics', () async {
      final _FakeApi api = _FakeApi(getResult: _rec(synced: '[00:01.00]hi'));
      final RawLyrics? raw = await source(api).resolve(_track);
      expect(raw!.source, LyricsSource.online);
      expect(raw.text, contains('[00:01.00]hi'));
      expect(api.searchCalls, 0); // exact hit → no search
    });

    test('instrumental flag returns an instrumental result', () async {
      final _FakeApi api = _FakeApi(getResult: _rec(instrumental: true));
      final RawLyrics? raw = await source(api).resolve(_track);
      expect(raw!.instrumental, isTrue);
    });

    test('plain-only record returns online (unsynced) lyrics', () async {
      final _FakeApi api = _FakeApi(getResult: _rec(plain: 'just words'));
      final RawLyrics? raw = await source(api).resolve(_track);
      expect(raw!.source, LyricsSource.online);
      expect(raw.text, 'just words');
    });

    test('a 404 (null get) falls back to a scored search', () async {
      final _FakeApi api = _FakeApi(
        getResult: null,
        searchResults: <LrclibRecord>[_rec(dur: 200, synced: '[00:02.00]x')],
      );
      final RawLyrics? raw = await source(api).resolve(_track);
      expect(api.searchCalls, 1);
      expect(raw!.text, contains('[00:02.00]x'));
    });

    test('search with no confident candidate → miss (null)', () async {
      final _FakeApi api = _FakeApi(
        getResult: null,
        searchResults: <LrclibRecord>[_rec(dur: 230, synced: '[00:01.00]x')],
      );
      expect(await source(api).resolve(_track), isNull);
    });

    test('a transport error propagates (abstain, not a miss)', () async {
      final _FakeApi api = _FakeApi(throwOnGet: true);
      await expectLater(source(api).resolve(_track), throwsException);
    });

    test('wifi-only on a metered network abstains before any request',
        () async {
      final _FakeApi api = _FakeApi(getResult: _rec(synced: '[00:01.00]hi'));
      await expectLater(
        source(api, wifiOnly: true, unmetered: false).resolve(_track),
        throwsA(isA<Exception>()),
      );
      expect(api.getCalls, 0);
    });

    test('wifi-only on wifi proceeds', () async {
      final _FakeApi api = _FakeApi(getResult: _rec(synced: '[00:01.00]hi'));
      final RawLyrics? raw =
          await source(api, wifiOnly: true, unmetered: true).resolve(_track);
      expect(raw, isNotNull);
    });

    test('an unusable query (unknown artist) is a miss without any request',
        () async {
      const Track noArtist = Track(
        id: 'local:2',
        source: TrackSource.local,
        title: 'Song',
        albumId: 'a',
        artistId: 'ar',
        artistName: '<unknown>',
        durationMs: 200000,
      );
      final _FakeApi api = _FakeApi(getResult: _rec());
      expect(await source(api).resolve(noArtist), isNull);
      expect(api.getCalls, 0);
    });
  });
}
