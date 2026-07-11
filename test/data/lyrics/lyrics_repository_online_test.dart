import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/lyrics/lyrics_repository.dart';
import 'package:viby/data/models/track.dart';

/// A resolver returning a fixed result (or throwing to "abstain"), counting
/// calls; an optional gate lets a test hold a call open (concurrency).
class _FakeSource implements LyricsSourceResolver {
  _FakeSource(this.result, {this.throws = false, this.gate});
  RawLyrics? result;
  bool throws;
  Future<void>? gate;
  int calls = 0;

  @override
  Future<RawLyrics?> resolve(Track track) async {
    calls++;
    if (gate != null) await gate;
    if (throws) throw Exception('offline');
    return result;
  }
}

const RawLyrics _online =
    RawLyrics(text: '[00:01.00]online', source: LyricsSource.online);
const RawLyrics _sidecar =
    RawLyrics(text: '[00:01.00]sidecar', source: LyricsSource.sidecarLrc);

const Track _track = Track(
  id: 'local:1',
  source: TrackSource.local,
  title: 'T',
  albumId: 'a',
  artistId: 'ar',
  filePath: '/m/s.mp3',
);

void main() {
  late VibyDatabase db;

  setUp(() async {
    db = VibyDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO tracks (id, source, title, album_id, artist_id, track_no, "
      "disc_no, duration_ms, date_added, date_modified, playable) "
      "VALUES ('local:1','local','T','a','ar',0,0,1000,0,0,1)",
    );
  });

  tearDown(() async => db.close());

  LyricsRepository repo(List<LyricsSourceResolver> sources) =>
      LyricsRepository(dao: db.lyricsDao, sources: sources);

  test('online is last in the chain; a hit caches source=online', () async {
    final Lyrics lyrics = await repo(<LyricsSourceResolver>[
      _FakeSource(null), // sidecar miss
      _FakeSource(_online),
    ]).lyricsFor(_track);
    expect(lyrics.isOnline, isTrue);
    expect(lyrics.lines.single.text, 'online');
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row!.source, LyricsSource.online);
    expect(row.expiresAt, isNull); // positive result never expires
  });

  test('instrumental flag caches an instrumental state (permanent)', () async {
    final _FakeSource src = _FakeSource(const RawLyrics.instrumental());
    final LyricsRepository r = repo(<LyricsSourceResolver>[src]);
    final Lyrics lyrics = await r.lyricsFor(_track);
    expect(lyrics.isInstrumental, isTrue);
    expect(lyrics.isEmpty, isTrue);
    // Cached: a second read doesn't re-consult the source.
    final Lyrics again = await r.lyricsFor(_track);
    expect(again.isInstrumental, isTrue);
    expect(src.calls, 1);
  });

  test('a definitive miss writes a negative cache WITH a TTL', () async {
    await repo(<LyricsSourceResolver>[_FakeSource(null)]).lyricsFor(_track);
    final row = await db.lyricsDao.getForTrack('local:1');
    expect(row!.source, LyricsSource.none);
    expect(row.expiresAt, isNotNull);
    expect(row.expiresAt!.isAfter(DateTime.now()), isTrue);
  });

  test('an abstaining (throwing) source does NOT write a negative cache',
      () async {
    final Lyrics lyrics =
        await repo(<LyricsSourceResolver>[_FakeSource(null, throws: true)])
            .lyricsFor(_track);
    expect(lyrics.isEmpty, isTrue);
    expect(lyrics.isInstrumental, isFalse);
    // No row persisted → it will retry next time (offline degrade).
    expect(await db.lyricsDao.getForTrack('local:1'), isNull);
  });

  test('an expired negative cache is re-resolved', () async {
    // Seed a stale none row (expired an hour ago).
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final _FakeSource src = _FakeSource(_online);
    final Lyrics lyrics = await repo(<LyricsSourceResolver>[src]).lyricsFor(_track);
    expect(src.calls, 1); // stale cache ignored → source consulted
    expect(lyrics.isOnline, isTrue);
  });

  test('a fresh negative cache is honoured (source not consulted)', () async {
    await db.lyricsDao.upsert(
      trackId: 'local:1',
      source: LyricsSource.none,
      synced: false,
      rawText: '',
      parsedOk: false,
      expiresAt: DateTime.now().add(const Duration(days: 14)),
    );
    final _FakeSource src = _FakeSource(_online);
    await repo(<LyricsSourceResolver>[src]).lyricsFor(_track);
    expect(src.calls, 0);
  });

  test('local beats online: after a rescan drops the row, sidecar wins',
      () async {
    // A cached online result...
    final LyricsRepository r1 = repo(<LyricsSourceResolver>[
      _FakeSource(null),
      _FakeSource(_online),
    ]);
    expect((await r1.lyricsFor(_track)).isOnline, isTrue);

    // The incremental scanner drops the row when the file changed...
    await db.lyricsDao.deleteForTrack('local:1');

    // ...and now a sidecar exists → it outranks online (chain order).
    final Lyrics upgraded = await repo(<LyricsSourceResolver>[
      _FakeSource(_sidecar),
      _FakeSource(_online),
    ]).lyricsFor(_track);
    expect(upgraded.source, LyricsSource.sidecarLrc);
    expect(upgraded.lines.single.text, 'sidecar');
  });

  test('concurrent resolves for one track fetch only once', () async {
    final Completer<void> gate = Completer<void>();
    final _FakeSource src = _FakeSource(_online, gate: gate.future);
    final LyricsRepository r = repo(<LyricsSourceResolver>[src]);

    final Future<Lyrics> a = r.lyricsFor(_track);
    final Future<Lyrics> b = r.lyricsFor(_track);
    gate.complete();
    final List<Lyrics> results = await Future.wait(<Future<Lyrics>>[a, b]);

    expect(src.calls, 1); // de-duplicated
    expect(results[0].isOnline, isTrue);
    expect(results[1].isOnline, isTrue);
  });
}
