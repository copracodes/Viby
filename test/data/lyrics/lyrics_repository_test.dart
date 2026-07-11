import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/lyrics/lyrics_repository.dart';
import 'package:viby/data/models/track.dart';

/// A [LyricsSourceResolver] that returns a fixed result and counts calls.
class _FakeSource implements LyricsSourceResolver {
  _FakeSource(this.result);
  final RawLyrics? result;
  int calls = 0;

  @override
  Future<RawLyrics?> resolve(Track track) async {
    calls++;
    return result;
  }
}

class _ThrowingSource implements LyricsSourceResolver {
  int calls = 0;
  @override
  Future<RawLyrics?> resolve(Track track) async {
    calls++;
    throw StateError('boom');
  }
}

const RawLyrics _sidecarHit =
    RawLyrics(text: '[00:01.00]sidecar', source: LyricsSource.sidecarLrc);
const RawLyrics _embeddedHit =
    RawLyrics(text: 'plain embedded', source: LyricsSource.embeddedUnsynced);

const Track _track = Track(
  id: 'local:1',
  source: TrackSource.local,
  title: 'T',
  albumId: 'a',
  artistId: 'ar',
  filePath: '/music/song.mp3',
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

  test('sidecar wins over embedded (priority = source order)', () async {
    final _FakeSource sidecar = _FakeSource(_sidecarHit);
    final _FakeSource embedded = _FakeSource(_embeddedHit);
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[sidecar, embedded],
    );

    final Lyrics lyrics = await repo.lyricsFor(_track);
    expect(lyrics.source, LyricsSource.sidecarLrc);
    expect(lyrics.isSynced, isTrue);
    expect(lyrics.lines.single.text, 'sidecar');
    expect(embedded.calls, 0); // never consulted — sidecar hit first
  });

  test('falls through to embedded when sidecar misses', () async {
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[
        _FakeSource(null),
        _FakeSource(_embeddedHit),
      ],
    );
    final Lyrics lyrics = await repo.lyricsFor(_track);
    expect(lyrics.source, LyricsSource.embeddedUnsynced);
    expect(lyrics.isSynced, isFalse);
    expect(lyrics.lines.single.text, 'plain embedded');
  });

  test('a throwing source is skipped, not fatal', () async {
    final _ThrowingSource bad = _ThrowingSource();
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[bad, _FakeSource(_embeddedHit)],
    );
    final Lyrics lyrics = await repo.lyricsFor(_track);
    expect(bad.calls, 1);
    expect(lyrics.source, LyricsSource.embeddedUnsynced);
  });

  test('total miss caches a negative marker; sources not re-consulted',
      () async {
    final _FakeSource sidecar = _FakeSource(null);
    final _FakeSource embedded = _FakeSource(null);
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[sidecar, embedded],
    );

    final Lyrics first = await repo.lyricsFor(_track);
    expect(first.isEmpty, isTrue);
    expect(first.source, LyricsSource.none);

    final Lyrics second = await repo.lyricsFor(_track);
    expect(second.isEmpty, isTrue);
    // Cached: the sources were consulted only once total.
    expect(sidecar.calls, 1);
    expect(embedded.calls, 1);
  });

  test('a cache hit avoids re-resolving', () async {
    final _FakeSource sidecar = _FakeSource(_sidecarHit);
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[sidecar],
    );
    await repo.lyricsFor(_track);
    final Lyrics again = await repo.lyricsFor(_track);
    expect(again.source, LyricsSource.sidecarLrc);
    expect(again.lines.single.text, 'sidecar');
    expect(sidecar.calls, 1); // second read came from cache
  });

  test('refresh drops the cache and re-resolves', () async {
    final _FakeSource sidecar = _FakeSource(_sidecarHit);
    final LyricsRepository repo = LyricsRepository(
      dao: db.lyricsDao,
      sources: <LyricsSourceResolver>[sidecar],
    );
    await repo.lyricsFor(_track);
    await repo.refresh(_track);
    expect(sidecar.calls, 2); // resolved again after refresh
  });
}
