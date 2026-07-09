import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/messenger.dart';
import '../core/router.dart';
import '../data/sources/local/media_store_observer.dart';
import '../data/sources/local/permission_service.dart';
import 'library_providers.dart';

part 'scan_triggers.g.dart';

/// How long after a scan an app-resume rescan is worthwhile. Resumes sooner than
/// this are skipped (the library is already fresh).
const Duration kResumeScanGap = Duration(minutes: 5);

/// Quiet period the media-change observer waits out before rescanning — a
/// download fires a burst of ticks; we rescan once after they settle.
const Duration kMediaSettleDelay = Duration(seconds: 3);

/// Whether an app-resume incremental rescan should run: no prior scan, or the
/// last one was longer ago than [gap]. Pure.
bool shouldResumeScan(
  DateTime? lastScan,
  DateTime now, {
  Duration gap = kResumeScanGap,
}) {
  if (lastScan == null) return true;
  return now.difference(lastScan) > gap;
}

/// Whether to surface the "N songs added" snackbar: some tracks were added AND
/// the user is looking at the Library tab (announcing elsewhere would be noise).
/// Pure.
bool shouldAnnounceAdded(int added, bool onLibrary) => added > 0 && onLibrary;

/// Whether the current route is within the Library tab.
bool _onLibraryTab() {
  try {
    final String path =
        appRouter.routerDelegate.currentConfiguration.uri.path;
    return path.startsWith('/library');
  } catch (_) {
    return false;
  }
}

/// The native MediaStore change observer (EventChannel wrapper).
@Riverpod(keepAlive: true)
MediaStoreObserver mediaStoreObserver(Ref ref) => MediaStoreObserver();

/// Subscribes to native MediaStore audio changes and, once permission is
/// granted, runs a debounced incremental rescan on each change so new music
/// appears within seconds. Started once at boot and kept alive. Never overlaps a
/// running scan (the notifier/`_scanning` guard no-ops a concurrent scan).
@Riverpod(keepAlive: true)
class MediaWatcher extends _$MediaWatcher {
  StreamSubscription<void>? _sub;
  ScanDebouncer? _debouncer;

  @override
  void build() {
    _debouncer = ScanDebouncer(
      kMediaSettleDelay,
      () => unawaited(ref.read(libraryScanProvider.notifier).incrementalRescan()),
    );
    ref.onDispose(() {
      _sub?.cancel();
      _debouncer?.dispose();
    });

    // Subscribe now if permission is already granted, and again if/when it's
    // granted later (first run).
    if (ref.read(audioPermissionProvider).valueOrNull ==
        AudioPermissionStatus.granted) {
      _subscribe();
    }
    ref.listen<AsyncValue<AudioPermissionStatus>>(audioPermissionProvider, (
      AsyncValue<AudioPermissionStatus>? previous,
      AsyncValue<AudioPermissionStatus> next,
    ) {
      if (next.valueOrNull == AudioPermissionStatus.granted) _subscribe();
    });
  }

  void _subscribe() {
    if (_sub != null) return;
    _sub = ref
        .read(mediaStoreObserverProvider)
        .changes()
        .listen((_) => _debouncer?.ping());
  }
}

/// Watches finished scans and, when an auto-detected rescan added new tracks
/// while the user is browsing the Library, shows a subtle snackbar. Mirrors the
/// FaultReporter pattern; started once at app boot and kept alive.
@Riverpod(keepAlive: true)
class NewSongsReporter extends _$NewSongsReporter {
  @override
  void build() {
    ref.listen<LibraryScanState>(libraryScanProvider, (
      LibraryScanState? previous,
      LibraryScanState next,
    ) {
      if (next is LibraryScanDone &&
          shouldAnnounceAdded(next.summary.added, _onLibraryTab())) {
        final int n = next.summary.added;
        rootMessengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(n == 1 ? '1 song added' : '$n songs added'),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    });
  }
}
