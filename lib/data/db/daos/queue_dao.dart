import 'dart:convert';

import 'package:drift/drift.dart';

import '../tables.dart';
import '../viby_database.dart';

part 'queue_dao.g.dart';

/// A restorable snapshot of the play queue.
class QueueSnapshot {
  const QueueSnapshot({
    required this.trackIds,
    required this.currentIndex,
    required this.positionMs,
    required this.shuffleOn,
    required this.repeatMode,
  });

  final List<String> trackIds;
  final int currentIndex;
  final int positionMs;
  final bool shuffleOn;
  final RepeatMode repeatMode;
}

/// Persists and restores the single-row queue state. Debouncing of saves is the
/// caller's concern (Phase 1.3).
@DriftAccessor(tables: <Type>[QueueState])
class QueueDao extends DatabaseAccessor<VibyDatabase> with _$QueueDaoMixin {
  QueueDao(super.db);

  static const int _singletonId = 0;

  Future<void> saveQueueState(QueueSnapshot snapshot) async {
    await into(queueState).insertOnConflictUpdate(
      QueueStateCompanion.insert(
        id: const Value(_singletonId),
        trackIds: jsonEncode(snapshot.trackIds),
        currentIndex: Value(snapshot.currentIndex),
        positionMs: Value(snapshot.positionMs),
        shuffleOn: Value(snapshot.shuffleOn),
        repeatMode: snapshot.repeatMode,
      ),
    );
  }

  Future<QueueSnapshot?> loadQueueState() async {
    final QueueStateRow? row =
        await (select(queueState)..where((t) => t.id.equals(_singletonId)))
            .getSingleOrNull();
    if (row == null) return null;
    final List<String> ids =
        (jsonDecode(row.trackIds) as List<dynamic>).cast<String>();
    return QueueSnapshot(
      trackIds: ids,
      currentIndex: row.currentIndex,
      positionMs: row.positionMs,
      shuffleOn: row.shuffleOn,
      repeatMode: row.repeatMode,
    );
  }
}
