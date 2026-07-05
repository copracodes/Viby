import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/sources/local/scan_diff.dart';

MediaSnapshotEntry _media(String id, int dateModified) =>
    MediaSnapshotEntry(id: id, dateModified: dateModified);

DbSnapshotEntry _db(
  String id,
  int dateModified, {
  TrackSource source = TrackSource.local,
}) =>
    DbSnapshotEntry(id: id, dateModified: dateModified, source: source);

void main() {
  group('computeScanDiff', () {
    test('detects newly added tracks', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 100), _media('local:2', 100)],
        <DbSnapshotEntry>[_db('local:1', 100)],
      );
      expect(diff.added, <String>{'local:2'});
      expect(diff.changed, isEmpty);
      expect(diff.deleted, isEmpty);
    });

    test('detects changed tracks by dateModified', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 200)],
        <DbSnapshotEntry>[_db('local:1', 100)],
      );
      expect(diff.added, isEmpty);
      expect(diff.changed, <String>{'local:1'});
      expect(diff.deleted, isEmpty);
    });

    test('detects deletions (in DB, gone from MediaStore)', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 100)],
        <DbSnapshotEntry>[_db('local:1', 100), _db('local:2', 100)],
      );
      expect(diff.added, isEmpty);
      expect(diff.changed, isEmpty);
      expect(diff.deleted, <String>{'local:2'});
    });

    test('leaves unchanged tracks untouched', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 100)],
        <DbSnapshotEntry>[_db('local:1', 100)],
      );
      expect(diff.isEmpty, isTrue);
    });

    test('never deletes subsonic rows absent from MediaStore', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 100)],
        <DbSnapshotEntry>[
          _db('local:1', 100),
          _db('subsonic:s1:5', 100, source: TrackSource.subsonic),
          _db('local:9', 100),
        ],
      );
      // Only the missing *local* row is deleted; the subsonic row is safe.
      expect(diff.deleted, <String>{'local:9'});
      expect(diff.deleted, isNot(contains('subsonic:s1:5')));
    });

    test('upserts combines added and changed', () {
      final ScanDiff diff = computeScanDiff(
        <MediaSnapshotEntry>[_media('local:1', 200), _media('local:2', 100)],
        <DbSnapshotEntry>[_db('local:1', 100)],
      );
      expect(diff.upserts, <String>{'local:1', 'local:2'});
    });
  });
}
