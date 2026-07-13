import 'dart:async';

import 'package:viby/audio/queue_playback_sink.dart';
import 'package:viby/data/db/tables.dart' show RepeatMode;
import 'package:viby/data/models/track.dart';

/// A recording fake [QueuePlaybackSink] so `QueueController`'s pure index math
/// (and widgets that read the queue) can be exercised without just_audio. It
/// never emits on [currentIndexStream] unless a test asks (via [emitIndex]), so
/// the controller's own computed state stays authoritative.
class FakeSink implements QueuePlaybackSink {
  final List<String> calls = <String>[];
  final StreamController<int?> _index = StreamController<int?>.broadcast();

  List<Track> lastLoaded = <Track>[];
  int lastInitialIndex = 0;
  Duration lastInitialPosition = Duration.zero;
  bool lastAutoPlay = false;
  List<Track> lastReorder = <Track>[];

  List<String> _ids(List<Track> ts) => ts.map((Track t) => t.id).toList();

  void emitIndex(int? i) => _index.add(i);

  @override
  Stream<int?> get currentIndexStream => _index.stream;

  /// The engine's repeat-aware "is there a next track" answer (the sleep timer's
  /// end-of-queue mode consumes it).
  bool hasNext = false;

  @override
  void setHasNext(bool value) => hasNext = value;

  @override
  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async {
    lastLoaded = List<Track>.of(tracks);
    lastInitialIndex = initialIndex;
    lastInitialPosition = initialPosition;
    lastAutoPlay = autoPlay;
    calls.add('load(${_ids(tracks).join(",")}|i=$initialIndex|a=$autoPlay)');
  }

  @override
  Future<void> insertTrack(int index, Track track) async =>
      calls.add('insert($index,${track.id})');

  @override
  Future<void> insertTracks(int index, List<Track> tracks) async =>
      calls.add('insertAll($index,${_ids(tracks).join(",")})');

  @override
  Future<void> removeTrackAt(int index) async => calls.add('remove($index)');

  @override
  Future<void> moveTrack(int from, int to) async =>
      calls.add('move($from,$to)');

  @override
  Future<void> reorderQueue(List<Track> newOrder) async {
    lastReorder = List<Track>.of(newOrder);
    calls.add('reorder(${_ids(newOrder).join(",")})');
  }

  @override
  Future<void> skipToIndex(int index) async => calls.add('skip($index)');

  @override
  Future<void> skipToNext() async => calls.add('next');

  @override
  Future<void> skipToPrevious() async => calls.add('prev');

  @override
  Future<void> clearQueue() async => calls.add('clear');

  @override
  Future<void> setRepeatMode(RepeatMode mode) async =>
      calls.add('repeat(${mode.name})');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek(${position.inMilliseconds})');
}
