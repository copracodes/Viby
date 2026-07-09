import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/tables.dart' show RepeatMode, TrackSource;
import 'package:viby/data/models/track.dart';
import 'package:viby/state/queue_provider.dart';

import '../support/fake_queue_sink.dart';

Track _t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id.toUpperCase(),
      albumId: 'album',
      artistId: 'artist',
      filePath: '/music/$id.mp3',
    );

List<Track> _tracks(String ids) =>
    ids.split('').map(_t).toList(growable: false);

/// Ids of the current queue, as a comma-free string for compact assertions.
String _order(QueueState s) => s.tracks.map((Track t) => t.id).join();

void main() {
  late FakeSink sink;
  late ProviderContainer container;
  late QueueController controller;

  QueueState state() => container.read(queueControllerProvider);

  setUp(() {
    sink = FakeSink();
    container = ProviderContainer(
      overrides: <Override>[queueSinkProvider.overrideWithValue(sink)],
    );
    addTearDown(container.dispose);
    controller = container.read(queueControllerProvider.notifier);
  });

  Future<void> seed(String ids, {int start = 0}) =>
      controller.setQueue(_tracks(ids), startIndex: start);

  group('setQueue', () {
    test('loads tracks and sets the current index', () async {
      await seed('abcde', start: 2);
      expect(_order(state()), 'abcde');
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
      expect(sink.lastLoaded.map((Track t) => t.id).join(), 'abcde');
      expect(sink.lastInitialIndex, 2);
    });

    test('shuffle keeps the start track as head and shuffles the rest',
        () async {
      await controller.setQueue(_tracks('abcde'), startIndex: 2, shuffle: true);
      expect(state().shuffleOn, isTrue);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'c');
      expect(state().tracks.first.id, 'c');
      expect(state().tracks.map((Track t) => t.id).toSet(),
          <String>{'a', 'b', 'c', 'd', 'e'});
    });
  });

  group('removeAt', () {
    test('before the current index shifts current down', () async {
      await seed('abcde', start: 2); // current = c
      await controller.removeAt(0); // drop a
      expect(_order(state()), 'bcde');
      expect(state().currentTrack?.id, 'c');
      expect(state().currentIndex, 1);
      expect(sink.calls, contains('remove(0)'));
    });

    test('after the current index leaves current unchanged', () async {
      await seed('abcde', start: 2); // current = c (index 2)
      await controller.removeAt(4); // drop e
      expect(_order(state()), 'abcd');
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
    });

    test('at the current index advances to the next track', () async {
      await seed('abcde', start: 2); // current = c
      await controller.removeAt(2); // drop the playing track
      expect(_order(state()), 'abde');
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'd');
    });

    test('removing the last playing track stops when repeat is off', () async {
      await seed('abc', start: 2); // current = c (last)
      await controller.removeAt(2);
      expect(_order(state()), 'ab');
      expect(state().currentIndex, 1);
      expect(sink.calls, contains('pause'));
    });

    test('removing the last playing track wraps when repeat is all', () async {
      await seed('abc', start: 2);
      await controller.cycleRepeat(); // off -> all
      await controller.removeAt(2);
      expect(_order(state()), 'ab');
      expect(state().currentIndex, 0); // wrapped to head
      expect(sink.calls, contains('skip(0)'));
    });
  });

  group('removeTrackById (hide a song)', () {
    test('removing the playing track advances to the next', () async {
      await seed('abcde', start: 2); // current = c
      await controller.removeTrackById('c');
      expect(_order(state()), 'abde');
      expect(state().currentTrack?.id, 'd'); // advanced
    });

    test('removing a not-playing track leaves the current track playing',
        () async {
      await seed('abcde', start: 2); // current = c
      await controller.removeTrackById('a');
      expect(_order(state()), 'bcde');
      expect(state().currentTrack?.id, 'c');
    });

    test('removes every occurrence of the id', () async {
      await controller.setQueue(_tracks('abca'), startIndex: 1); // current = b
      await controller.removeTrackById('a');
      expect(_order(state()), 'bc');
      expect(state().currentTrack?.id, 'b');
    });

    test('a missing id is a no-op', () async {
      await seed('abc', start: 1);
      await controller.removeTrackById('z');
      expect(_order(state()), 'abc');
      expect(state().currentTrack?.id, 'b');
    });
  });

  group('reorder', () {
    test('moving an item across the current index (forward) tracks current',
        () async {
      await seed('abcde', start: 2); // current = c
      await controller.reorder(0, 3); // a -> after removal index 3
      expect(_order(state()), 'bcdae');
      expect(state().currentTrack?.id, 'c');
      expect(state().currentIndex, 1);
      expect(sink.calls, contains('move(0,3)'));
    });

    test('moving an item across the current index (backward) tracks current',
        () async {
      await seed('abcde', start: 2); // current = c
      await controller.reorder(4, 0); // e -> front
      expect(_order(state()), 'eabcd');
      expect(state().currentTrack?.id, 'c');
      expect(state().currentIndex, 3);
    });

    test('moving the current item itself follows it', () async {
      await seed('abcde', start: 2); // current = c
      await controller.reorder(2, 4);
      expect(_order(state()), 'abdec');
      expect(state().currentTrack?.id, 'c');
      expect(state().currentIndex, 4);
    });
  });

  group('shuffle / un-shuffle', () {
    test('shuffle keeps the current track; un-shuffle restores order + index',
        () async {
      await seed('abcde', start: 2); // current = c

      await controller.toggleShuffle();
      expect(state().shuffleOn, isTrue);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'c');
      expect(state().tracks.first.id, 'c');
      expect(state().tracks.map((Track t) => t.id).toSet(),
          <String>{'a', 'b', 'c', 'd', 'e'});
      expect(sink.lastReorder.first.id, 'c');

      await controller.toggleShuffle();
      expect(state().shuffleOn, isFalse);
      expect(_order(state()), 'abcde');
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
    });
  });

  group('playNow', () {
    test('on an empty queue starts a new autoplaying queue', () async {
      await controller.playNow(_t('x'));
      expect(_order(state()), 'x');
      expect(state().currentIndex, 0);
      expect(sink.lastAutoPlay, isTrue);
    });

    test('on a non-empty queue inserts after current and jumps to it',
        () async {
      await seed('abc', start: 0); // current = a
      await controller.playNow(_t('x'));
      expect(_order(state()), 'axbc');
      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'x');
      expect(sink.calls, containsAllInOrder(<String>['insert(1,x)', 'skip(1)', 'play']));
    });
  });

  group('playNext / addToQueue', () {
    test('playNext inserts after current without moving current', () async {
      await seed('abc', start: 1); // current = b
      await controller.playNext(_t('x'));
      expect(_order(state()), 'abxc');
      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
    });

    test('addToQueue appends to the end', () async {
      await seed('abc', start: 1);
      await controller.addToQueue(_tracks('xy'));
      expect(_order(state()), 'abcxy');
      expect(state().currentIndex, 1);
    });
  });

  group('cycleRepeat', () {
    test('cycles off -> all -> one -> off and mirrors to the sink', () async {
      await seed('abc');
      expect(state().repeatMode, RepeatMode.off);
      await controller.cycleRepeat();
      expect(state().repeatMode, RepeatMode.all);
      await controller.cycleRepeat();
      expect(state().repeatMode, RepeatMode.one);
      await controller.cycleRepeat();
      expect(state().repeatMode, RepeatMode.off);
      expect(sink.calls,
          containsAllInOrder(<String>['repeat(all)', 'repeat(one)', 'repeat(off)']));
    });
  });

  group('currentIndexStream reconciliation (auto-advance)', () {
    test('a player index change updates current without touching order',
        () async {
      await seed('abcde', start: 0);
      sink.emitIndex(3);
      await Future<void>.delayed(Duration.zero);
      expect(state().currentIndex, 3);
      expect(state().currentTrack?.id, 'd');
      expect(_order(state()), 'abcde');
    });
  });

  group('clear', () {
    test('empties the queue and stops', () async {
      await seed('abc');
      await controller.clear();
      expect(state().isEmpty, isTrue);
      expect(state().currentIndex, -1);
      expect(sink.calls, contains('clear'));
    });
  });
}
