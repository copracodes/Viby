import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/messenger.dart';
import '../core/router.dart';
import 'library_providers.dart';

part 'scan_triggers.g.dart';

/// How long after a scan an app-resume rescan is worthwhile. Resumes sooner than
/// this are skipped (the library is already fresh).
const Duration kResumeScanGap = Duration(minutes: 5);

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
