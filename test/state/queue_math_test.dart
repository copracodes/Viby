import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show RepeatMode, TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/queue_provider.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      albumId: 'album',
      artistId: 'artist',
    );

void main() {
  group('nextIndexAfterEnd (auto-advance rule per repeat mode)', () {
    test('repeat off: advances until the end, then stops (null)', () {
      expect(nextIndexAfterEnd(0, 3, RepeatMode.off), 1);
      expect(nextIndexAfterEnd(1, 3, RepeatMode.off), 2);
      expect(nextIndexAfterEnd(2, 3, RepeatMode.off), isNull);
    });

    test('repeat all: wraps past the end back to 0', () {
      expect(nextIndexAfterEnd(1, 3, RepeatMode.all), 2);
      expect(nextIndexAfterEnd(2, 3, RepeatMode.all), 0);
    });

    test('repeat one: stays on the current index', () {
      expect(nextIndexAfterEnd(2, 3, RepeatMode.one), 2);
      expect(nextIndexAfterEnd(0, 3, RepeatMode.one), 0);
    });

    test('empty queue always stops', () {
      expect(nextIndexAfterEnd(0, 0, RepeatMode.all), isNull);
    });
  });

  group('buildRestoredQueue (restore drops missing ids + clamps index)', () {
    Map<String, Track> byId(String ids) =>
        <String, Track>{for (final String id in ids.split('')) id: _t(id)};

    test('all ids present: order and index preserved', () {
      final RestoredQueue r = buildRestoredQueue(
        trackIds: <String>['a', 'b', 'c'],
        savedIndex: 1,
        byId: byId('abc'),
      );
      expect(r.tracks.map((Track t) => t.id).join(), 'abc');
      expect(r.currentIndex, 1);
    });

    test('saved current track deleted: anchors to nearest earlier survivor', () {
      final RestoredQueue r = buildRestoredQueue(
        trackIds: <String>['a', 'b', 'c', 'd'],
        savedIndex: 2, // c, which is gone
        byId: byId('abd'),
      );
      expect(r.tracks.map((Track t) => t.id).join(), 'abd');
      expect(r.currentIndex, 1); // b, the nearest survivor at/ before c
    });

    test('all tracks before current deleted: anchors to first survivor', () {
      final RestoredQueue r = buildRestoredQueue(
        trackIds: <String>['a', 'b', 'c'],
        savedIndex: 2,
        byId: byId('c'),
      );
      expect(r.tracks.map((Track t) => t.id).join(), 'c');
      expect(r.currentIndex, 0);
    });

    test('everything deleted: empty queue, index -1', () {
      final RestoredQueue r = buildRestoredQueue(
        trackIds: <String>['a', 'b'],
        savedIndex: 1,
        byId: <String, Track>{},
      );
      expect(r.tracks, isEmpty);
      expect(r.currentIndex, -1);
    });

    test('saved index past the surviving end clamps down', () {
      final RestoredQueue r = buildRestoredQueue(
        trackIds: <String>['a', 'b', 'c'],
        savedIndex: 2, // c survives and is last
        byId: byId('ab'), // c dropped
      );
      expect(r.tracks.map((Track t) => t.id).join(), 'ab');
      expect(r.currentIndex, 1);
    });
  });
}
