import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart';
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/delete_targets.dart';
import 'package:viby/data/sources/local/song_mapper.dart';

TrackRow _row(String id, TrackSource source, {String? path = '/music/a.mp3'}) =>
    TrackRow(
      id: id,
      source: source,
      title: id,
      albumId: 'album',
      artistId: 'artist',
      filePath: path,
      trackNo: 0,
      discNo: 0,
      durationMs: 1000,
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
      playable: true,
      visibility: TrackVisibility.visible,
      userOverride: false,
      liked: false,
      rgScanned: false,
    );

void main() {
  group('mediaStoreIdFromTrackId', () {
    test('parses a local id back to its MediaStore row id', () {
      expect(mediaStoreIdFromTrackId(localTrackId(42)), 42);
    });

    test('returns null for ids with no MediaStore row behind them', () {
      expect(mediaStoreIdFromTrackId('subsonic:s1:99'), isNull);
      expect(mediaStoreIdFromTrackId('local:synthetic:7'), isNull);
      expect(mediaStoreIdFromTrackId('local:'), isNull);
      expect(mediaStoreIdFromTrackId('42'), isNull);
    });
  });

  group('resolveDeleteTargets (the source guard)', () {
    test('keeps local MediaStore-backed tracks, index-aligned', () {
      final DeleteTargets targets = resolveDeleteTargets(<TrackRow>[
        _row('local:1', TrackSource.local, path: '/music/one.mp3'),
        _row('local:2', TrackSource.local, path: '/music/two.mp3'),
      ]);

      expect(targets.trackIds, <String>['local:1', 'local:2']);
      expect(targets.mediaIds, <int>[1, 2]);
      expect(targets.paths, <String>['/music/one.mp3', '/music/two.mp3']);
      expect(targets.skipped, 0);
      expect(targets.length, 2);
    });

    test('a subsonic track can never reach the platform delete', () {
      final DeleteTargets targets = resolveDeleteTargets(<TrackRow>[
        _row('subsonic:s1:77', TrackSource.subsonic),
      ]);

      expect(targets.isEmpty, isTrue);
      expect(targets.mediaIds, isEmpty);
      expect(targets.skipped, 1);
    });

    test('synthetic seeded rows are rejected (no MediaStore id)', () {
      final DeleteTargets targets = resolveDeleteTargets(<TrackRow>[
        _row('local:synthetic:3', TrackSource.local),
      ]);

      expect(targets.isEmpty, isTrue);
      expect(targets.skipped, 1);
    });

    test('a mixed selection deletes only the deletable part', () {
      final DeleteTargets targets = resolveDeleteTargets(<TrackRow>[
        _row('local:5', TrackSource.local),
        _row('subsonic:s1:77', TrackSource.subsonic),
        _row('local:6', TrackSource.local, path: null),
      ]);

      expect(targets.trackIds, <String>['local:5', 'local:6']);
      expect(targets.mediaIds, <int>[5, 6]);
      expect(targets.paths, <String?>['/music/a.mp3', null]);
      expect(targets.skipped, 1);
    });
  });
}
