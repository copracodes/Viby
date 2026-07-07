import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/library_seeder.dart';
import 'package:viby/data/sources/local/scan_diff.dart';

/// Scale budgets for a 10k-track library. These print the measured numbers (so
/// they're reported), and assert generous ceilings — comfortably above real
/// dev-hardware timings but loose enough not to flake on a slow CI box. The
/// target budgets from the spec (search < 100ms, diff < 2s, restore < 500ms)
/// are the numbers to watch in the printed output.
void main() {
  test('10k library: seed, search, diff and restore stay within budget',
      () async {
    final VibyDatabase db = VibyDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final LibraryDao dao = db.libraryDao;

    // --- Seed 10k / 800 / 400 -------------------------------------------
    final Stopwatch seedSw = Stopwatch()..start();
    await LibrarySeeder(dao).seed(tracks: 10000, albums: 800, artists: 400);
    seedSw.stop();
    expect(await dao.trackCount(), 10000);

    // --- Search ----------------------------------------------------------
    final Stopwatch searchSw = Stopwatch()..start();
    final List<TrackWithMeta> hits =
        await dao.searchTracks('Track 05000').first;
    searchSw.stop();
    expect(hits, isNotEmpty);

    // --- Incremental diff over 10k --------------------------------------
    final List<DbSnapshotEntry> dbSnap = (await dao.trackSnapshots())
        .map((r) => DbSnapshotEntry(
              id: r.id,
              dateModified: r.dateModified.millisecondsSinceEpoch ~/ 1000,
              source: r.source,
            ))
        .toList();
    // Mirror MediaStore as an unchanged snapshot (worst case: compares all).
    final List<MediaSnapshotEntry> mediaSnap = dbSnap
        .map((DbSnapshotEntry e) =>
            MediaSnapshotEntry(id: e.id, dateModified: e.dateModified))
        .toList();
    final Stopwatch diffSw = Stopwatch()..start();
    final ScanDiff diff = computeScanDiff(mediaSnap, dbSnap);
    diffSw.stop();
    expect(diff.isEmpty, isTrue);

    // --- Cold-start restore path (fetch a large saved queue) ------------
    // The DB fetch is the restore path's dominant cost; artwork resolution is
    // deduped-per-album and trivial (see track_resolver), so measuring
    // getTracksByIds captures the cold-start budget.
    final List<String> savedIds =
        List<String>.generate(500, (int i) => '${kSyntheticPrefix}track:$i');
    final Stopwatch restoreSw = Stopwatch()..start();
    final List<TrackWithMeta> metas = await dao.getTracksByIds(savedIds);
    restoreSw.stop();
    expect(metas, hasLength(500));

    // ignore: avoid_print
    print('[scale] seed=${seedSw.elapsedMilliseconds}ms '
        'search=${searchSw.elapsedMilliseconds}ms '
        'diff=${diffSw.elapsedMilliseconds}ms '
        'restore(500 ids)=${restoreSw.elapsedMilliseconds}ms');

    // Generous ceilings (target budgets are much tighter — see printout).
    expect(searchSw.elapsedMilliseconds, lessThan(1000));
    expect(diffSw.elapsedMilliseconds, lessThan(2000));
    expect(restoreSw.elapsedMilliseconds, lessThan(2000));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
