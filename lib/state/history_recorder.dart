import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/player_service.dart' show VibyProcessingState;
import '../data/db/daos/history_dao.dart';
import 'database_providers.dart';
import 'player_providers.dart';
import 'queue_provider.dart';

part 'history_recorder.g.dart';

/// Fraction of a track that must play before it counts as a "play".
const double _kPlayThreshold = 0.8;

/// Logs a play to [HistoryDao] when a track reaches [_kPlayThreshold] of its
/// duration OR completes — whichever happens first — recording **at most once
/// per index-session** (one queue-item playthrough).
///
/// It is driven purely by playback signals (current index, position, duration,
/// completion), not by UI events: seeking back and forth within a track can
/// never double-count, a track skipped before the threshold is never recorded,
/// and a cold-start restore (paused, position not advancing) records nothing.
class HistoryRecorder {
  HistoryRecorder(this._dao);

  final HistoryDao _dao;

  /// The queue index of the current playthrough. A change of index starts a
  /// fresh session and re-arms recording.
  int? _sessionIndex;
  String? _trackId;
  int _durationMs = 0;
  bool _recorded = false;

  /// Called when the playing queue item changes (index-session boundary).
  void onIndexChanged(int? index, String? trackId) {
    if (index != _sessionIndex) {
      _sessionIndex = index;
      _recorded = false;
    }
    _trackId = trackId;
  }

  void onDurationChanged(Duration? duration) {
    _durationMs = duration?.inMilliseconds ?? 0;
  }

  void onPositionChanged(Duration position) {
    if (_recorded || _trackId == null || _durationMs <= 0) return;
    if (position.inMilliseconds >= _durationMs * _kPlayThreshold) {
      _record(completed: false);
    }
  }

  /// The source reached its end (processing state completed).
  void onCompleted() {
    if (_recorded || _trackId == null) return;
    _record(completed: true);
  }

  void _record({required bool completed}) {
    final String? id = _trackId;
    if (id == null) return;
    _recorded = true;
    unawaited(_dao.recordPlay(trackId: id, completed: completed));
  }
}

/// Wires the recorder to the playback + queue streams. Read once at app start.
@Riverpod(keepAlive: true)
HistoryRecorder historyRecorder(Ref ref) {
  final HistoryRecorder recorder =
      HistoryRecorder(ref.watch(vibyDatabaseProvider).historyDao);
  ref.listen<QueueState>(
    queueControllerProvider,
    (_, QueueState next) => recorder.onIndexChanged(
      next.isEmpty ? null : next.currentIndex,
      next.currentTrack?.id,
    ),
    fireImmediately: true,
  );
  ref.listen<AsyncValue<Duration?>>(
    trackDurationProvider,
    (_, AsyncValue<Duration?> next) =>
        recorder.onDurationChanged(next.valueOrNull),
  );
  ref.listen<AsyncValue<Duration>>(
    positionProvider,
    (_, AsyncValue<Duration> next) =>
        recorder.onPositionChanged(next.valueOrNull ?? Duration.zero),
  );
  ref.listen<AsyncValue<VibyProcessingState>>(
    processingStateProvider,
    (_, AsyncValue<VibyProcessingState> next) {
      if (next.valueOrNull == VibyProcessingState.completed) {
        recorder.onCompleted();
      }
    },
  );
  return recorder;
}
