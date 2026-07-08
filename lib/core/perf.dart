import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Lightweight, release-safe performance instrumentation. Everything here is
/// gated so it costs nothing in a release build; it exists to put real numbers
/// in `logcat` during the profile-mode device pass (no DevTools needed).

/// Cold-start stopwatch — started at the very top of `main()`.
final Stopwatch coldStartWatch = Stopwatch()..start();

/// Logs time from process start to the first rendered frame, once. Call from the
/// root widget's first post-frame callback.
void reportColdStart() {
  if (kReleaseMode || !coldStartWatch.isRunning) return;
  coldStartWatch.stop();
  debugPrint(
    '[viby.perf] cold start → first frame: '
    '${coldStartWatch.elapsedMilliseconds}ms',
  );
}

/// In profile mode, tracks janky frames (build + raster > one 60fps budget) and
/// logs a rolling summary every ~120 frames.
void installFrameMonitor() {
  if (!kProfileMode) return;
  int total = 0;
  int janky = 0;
  double worst = 0;
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      final double frameMs =
          (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) /
              1000.0;
      total++;
      if (frameMs > 16.7) janky++;
      if (frameMs > worst) worst = frameMs;
    }
    if (total > 0 && total % 120 < timings.length) {
      debugPrint(
        '[viby.perf] frames=$total janky(>16.7ms)=$janky '
        '(${(100 * janky / total).toStringAsFixed(1)}%) '
        'worst=${worst.toStringAsFixed(1)}ms',
      );
    }
  });
}
