import '../data/db/tables.dart' show RepeatMode;
import '../data/models/track.dart';

/// The playback operations the queue engine (`QueueNotifier`) drives.
///
/// `PlayerService` implements this by delegating to the audio handler; tests
/// supply a fake so `QueueNotifier`'s pure index math can be verified without
/// just_audio. It intentionally carries only domain types (no just_audio /
/// audio_service leaks), matching CLAUDE.md's facade rule.
///
/// The engine owns queue *order* and *shuffle*; the sink only mirrors that order
/// into the player and reports the currently-playing index back via
/// [currentIndexStream] (for auto-advance and OS-media-session skips).
abstract interface class QueuePlaybackSink {
  /// Replaces the whole queue and (re)loads the player at [initialIndex],
  /// seeked to [initialPosition]. Starts playing iff [autoPlay].
  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex,
    Duration initialPosition,
    bool autoPlay,
  });

  /// In-place insert (gapless — never reloads the playing item).
  Future<void> insertTrack(int index, Track track);

  /// In-place insert of several tracks at [index].
  Future<void> insertTracks(int index, List<Track> tracks);

  /// In-place removal.
  Future<void> removeTrackAt(int index);

  /// In-place move (remove-then-insert semantics: [to] is the index in the
  /// list *after* removal).
  Future<void> moveTrack(int from, int to);

  /// Reorders the whole queue to match [newOrder] (a permutation of the current
  /// queue) using in-place moves, so the playing item is never reloaded.
  Future<void> reorderQueue(List<Track> newOrder);

  /// Jumps playback to queue index [index] (position 0).
  Future<void> skipToIndex(int index);

  Future<void> skipToNext();

  Future<void> skipToPrevious();

  /// Empties the queue and stops playback.
  Future<void> clearQueue();

  Future<void> setRepeatMode(RepeatMode mode);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// The currently-playing queue index (null when idle/empty). Fires on
  /// auto-advance and OS-media-session skips as well as engine-driven jumps.
  Stream<int?> get currentIndexStream;

  /// Whether a track follows the current one (repeat-aware). The engine owns
  /// this answer and pushes it down; the sleep timer's "end of queue" mode needs
  /// it, and the player alone can't compute it.
  void setHasNext(bool hasNext);
}
