import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/state/history_recorder.dart';

const int _durMs = 100000; // 100s track

TracksCompanion _track(String id) => TracksCompanion.insert(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album:1',
      artistId: 'artist:1',
      durationMs: const Value<int>(_durMs),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

void main() {
  late VibyDatabase db;

  setUp(() async {
    db = VibyDatabase.forTesting(NativeDatabase.memory());
    await db.libraryDao.upsertTracks(<TracksCompanion>[_track('t1'), _track('t2')]);
  });
  tearDown(() async => db.close());

  Future<int> plays(String trackId) async {
    final List<PlayHistoryRow> rows = await (db.select(db.playHistory)
          ..where((t) => t.trackId.equals(trackId)))
        .get();
    return rows.length;
  }

  test('records once at 80%; seek-back and forward never double-count',
      () async {
    final HistoryRecorder r = HistoryRecorder(db.historyDao);
    r.onIndexChanged(0, 't1');
    r.onDurationChanged(const Duration(milliseconds: _durMs));

    r.onPositionChanged(const Duration(milliseconds: 79000)); // < 80%
    await pumpEventQueue();
    expect(await plays('t1'), 0);

    r.onPositionChanged(const Duration(milliseconds: 80000)); // hits 80%
    await pumpEventQueue();
    expect(await plays('t1'), 1);

    r.onPositionChanged(const Duration(milliseconds: 10000)); // seek back
    r.onPositionChanged(const Duration(milliseconds: 95000)); // forward again
    await pumpEventQueue();
    expect(await plays('t1'), 1);
  });

  test('a track skipped before 80% is never recorded', () async {
    final HistoryRecorder r = HistoryRecorder(db.historyDao);
    r.onIndexChanged(0, 't1');
    r.onDurationChanged(const Duration(milliseconds: _durMs));
    r.onPositionChanged(const Duration(milliseconds: 50000)); // 50%
    r.onIndexChanged(1, 't2'); // skip to next queue item
    await pumpEventQueue();
    expect(await plays('t1'), 0);
  });

  test('completion records the play (marked completed) even below 80%',
      () async {
    final HistoryRecorder r = HistoryRecorder(db.historyDao);
    r.onIndexChanged(0, 't1');
    r.onDurationChanged(const Duration(milliseconds: _durMs));
    r.onPositionChanged(const Duration(milliseconds: 40000)); // 40%
    r.onCompleted();
    await pumpEventQueue();
    expect(await plays('t1'), 1);
    final PlayHistoryRow row = await (db.select(db.playHistory)
          ..where((t) => t.trackId.equals('t1')))
        .getSingle();
    expect(row.completed, isTrue);
  });

  test('each index-session records independently', () async {
    final HistoryRecorder r = HistoryRecorder(db.historyDao);
    r.onDurationChanged(const Duration(milliseconds: _durMs));

    r.onIndexChanged(0, 't1');
    r.onPositionChanged(const Duration(milliseconds: 85000));
    r.onIndexChanged(1, 't2');
    r.onPositionChanged(const Duration(milliseconds: 85000));
    await pumpEventQueue();

    expect(await plays('t1'), 1);
    expect(await plays('t2'), 1);
  });
}
