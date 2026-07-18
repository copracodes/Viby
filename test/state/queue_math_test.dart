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
  group('playNextTargetIndex (move a queued row to play next)', () {
    test('any row after the current lands at current + 1 (post-removal)', () {
      // current B (1): move a later row (4 or 3) → insert index 2 after removal.
      expect(playNextTargetIndex(4, 1), 2);
      expect(playNextTargetIndex(3, 1), 2);
      // current A (0): move row 2 → 1.
      expect(playNextTargetIndex(2, 0), 1);
    });

    test('a row before the current moves to current (post-removal shift)', () {
      // [A B C D], current C (2): move A (0). Removing A shifts C to 1, so the
      // post-removal insert index is 2 (right after C).
      expect(playNextTargetIndex(0, 2), 2);
      expect(playNextTargetIndex(1, 3), 3);
    });

    test('the current row, or the already-next row, is a no-op (null)', () {
      expect(playNextTargetIndex(2, 2), isNull); // is the current track
      // from == current + 1 → already immediately next → to == from → null.
      expect(playNextTargetIndex(2, 1), isNull);
      expect(playNextTargetIndex(3, 2), isNull);
      // But a row two past the current is a real move.
      expect(playNextTargetIndex(4, 2), 3);
    });
  });

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

  group('QueueState.hasNext / hasPrevious (transport affordance)', () {
    QueueState state(
      int count, {
      required int index,
      RepeatMode repeat = RepeatMode.off,
    }) =>
        QueueState(
          tracks: <Track>[for (int i = 0; i < count; i++) _t('$i')],
          currentIndex: index,
          shuffleOn: false,
          repeatMode: repeat,
        );

    test('single-track queue, repeat off: no next, no previous', () {
      final QueueState s = state(1, index: 0);
      expect(s.hasNext, isFalse);
      expect(s.hasPrevious, isFalse);
    });

    test('single-track queue, repeat all: next and previous wrap', () {
      final QueueState s = state(1, index: 0, repeat: RepeatMode.all);
      expect(s.hasNext, isTrue);
      expect(s.hasPrevious, isTrue);
    });

    test('multi-track, repeat off: bounded at the ends', () {
      expect(state(3, index: 0).hasPrevious, isFalse);
      expect(state(3, index: 0).hasNext, isTrue);
      expect(state(3, index: 2).hasNext, isFalse);
      expect(state(3, index: 2).hasPrevious, isTrue);
      expect(state(3, index: 1).hasNext, isTrue);
      expect(state(3, index: 1).hasPrevious, isTrue);
    });

    test('repeat one: always has next and previous (pins to current)', () {
      final QueueState s = state(3, index: 2, repeat: RepeatMode.one);
      expect(s.hasNext, isTrue);
      expect(s.hasPrevious, isTrue);
    });

    test('empty queue: neither', () {
      const QueueState s = QueueState.empty();
      expect(s.hasNext, isFalse);
      expect(s.hasPrevious, isFalse);
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
