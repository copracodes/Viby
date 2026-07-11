import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/lyrics/sources/lrclib_source.dart';
import 'package:viby/state/lyrics_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/ui/player/lyrics_follow.dart';

Lyrics _synced(List<int> starts) => Lyrics(
      lines:
          starts.map((int ms) => LyricLine(startMs: ms, text: 't$ms')).toList(),
      isSynced: true,
      source: LyricsSource.sidecarLrc,
    );

/// Lets pending stream events + provider rebuilds flush.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('lyricsActiveIndex tracks position and only fires on line changes',
      () async {
    final StreamController<Duration> pos = StreamController<Duration>();
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      currentLyricsProvider.overrideWith((ref) async => _synced(<int>[1000, 3000, 7000])),
      positionProvider.overrideWith((ref) => pos.stream),
    ]);
    addTearDown(container.dispose);
    addTearDown(pos.close);

    await container.read(currentLyricsProvider.future);

    final List<int> seen = <int>[];
    container.listen<int>(
      lyricsActiveIndexProvider,
      (int? _, int next) => seen.add(next),
      fireImmediately: true,
    );

    // Position ticks; ticks that don't cross a boundary must not re-notify.
    for (final int ms in <int>[500, 1000, 1500, 3000, 6999, 7000, 9000]) {
      pos.add(Duration(milliseconds: ms));
      await _settle();
    }

    // -1 (initial/before first), 0 (@1000, unchanged @1500), 1 (@3000, unchanged
    // @6999), 2 (@7000, unchanged @9000).
    expect(seen, <int>[-1, 0, 1, 2]);
  });

  test('unsynced lyrics never highlight (active index stays -1)', () async {
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      currentLyricsProvider.overrideWith((ref) async => const Lyrics(
            lines: <LyricLine>[LyricLine(startMs: 0, text: 'a')],
            isSynced: false,
            source: LyricsSource.embeddedUnsynced,
          )),
      positionProvider.overrideWith((ref) => Stream<Duration>.value(
            const Duration(seconds: 30),
          )),
    ]);
    addTearDown(container.dispose);

    await container.read(currentLyricsProvider.future);
    await _settle();
    expect(container.read(lyricsActiveIndexProvider), -1);
  });

  group('LyricsController.searchOnline', () {
    test('returns candidates from the API', () async {
      final ProviderContainer container = ProviderContainer(overrides: <Override>[
        lrclibApiProvider.overrideWithValue(_FakeApi(results: <LrclibRecord>[
          const LrclibRecord(
            trackName: 'Song',
            artistName: 'Artist',
            durationSec: 200,
            instrumental: false,
            plainLyrics: 'la la',
          ),
        ])),
      ]);
      addTearDown(container.dispose);

      final List<LrclibRecord> out = await container
          .read(lyricsControllerProvider.notifier)
          .searchOnline(track: 'Song', artist: 'Artist');
      expect(out, hasLength(1));
      expect(out.first.trackName, 'Song');
    });

    test('blank input short-circuits (never hits the API)', () async {
      final _FakeApi api = _FakeApi(results: const <LrclibRecord>[]);
      final ProviderContainer container = ProviderContainer(
          overrides: <Override>[lrclibApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      final List<LrclibRecord> out = await container
          .read(lyricsControllerProvider.notifier)
          .searchOnline(track: '  ', artist: '');
      expect(out, isEmpty);
      expect(api.searchCalls, 0);
    });

    test('an API failure yields an empty list (never throws to the UI)',
        () async {
      final ProviderContainer container = ProviderContainer(overrides: <Override>[
        lrclibApiProvider.overrideWithValue(_FakeApi(throwOnSearch: true)),
      ]);
      addTearDown(container.dispose);

      final List<LrclibRecord> out = await container
          .read(lyricsControllerProvider.notifier)
          .searchOnline(track: 'Song', artist: 'Artist');
      expect(out, isEmpty);
    });
  });

  group('LyricsFollowController', () {
    test('starts following; scroll pauses; resume/track-change follow again',
        () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(lyricsFollowControllerProvider).isFollowing, isTrue);

      final LyricsFollowController c =
          container.read(lyricsFollowControllerProvider.notifier);

      c.dispatch(LyricsFollowEvent.userScrolled);
      expect(
          container.read(lyricsFollowControllerProvider).showResumePill, isTrue);

      c.dispatch(LyricsFollowEvent.resumeTapped);
      expect(container.read(lyricsFollowControllerProvider).isFollowing, isTrue);

      c.dispatch(LyricsFollowEvent.userScrolled);
      c.dispatch(LyricsFollowEvent.trackChanged);
      expect(container.read(lyricsFollowControllerProvider).isFollowing, isTrue);
    });
  });
}

class _FakeApi implements LrclibApi {
  _FakeApi({this.results = const <LrclibRecord>[], this.throwOnSearch = false});

  final List<LrclibRecord> results;
  final bool throwOnSearch;
  int searchCalls = 0;

  @override
  Future<LrclibRecord?> get({
    required String track,
    required String artist,
    String? album,
    required int durationSec,
  }) async =>
      null;

  @override
  Future<List<LrclibRecord>> search({
    required String track,
    required String artist,
  }) async {
    searchCalls++;
    if (throwOnSearch) throw Exception('network');
    return results;
  }
}
