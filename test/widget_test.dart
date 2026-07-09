// Smoke test: the app boots into the shell (bottom nav) and, with an empty
// library and no permission yet, lands on Home showing the access call-to-action
// (the manual scan button is gone — the scan auto-starts once access is granted).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/app.dart';
import 'package:viby/data/sources/local/permission_service.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/state/player_providers.dart';
import 'package:viby/state/queue_provider.dart';

import 'support/fake_queue_sink.dart';

/// A permission service that never touches the platform channel — returns a
/// fixed status so the first-run UI is deterministic in tests.
class _FakePermissionService implements AudioPermissionService {
  _FakePermissionService(this._status);
  final AudioPermissionStatus _status;

  @override
  Future<AudioPermissionStatus> check() async => _status;
  @override
  Future<AudioPermissionStatus> request() async => _status;
  @override
  Future<bool> openSettings() async => false;
}

void main() {
  testWidgets('app boots to the shell with its nav destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // Playback wiring the shell/mini-player/history recorder touch.
          queueSinkProvider.overrideWithValue(FakeSink()),
          playingProvider.overrideWith((Ref ref) => Stream<bool>.value(false)),
          // Empty library → Home shows the first-run CTA (no DB access here).
          libraryTrackCountProvider
              .overrideWith((Ref ref) => Stream<int>.value(0)),
          // No permission yet → the access CTA (not the auto-scan progress).
          audioPermissionServiceProvider.overrideWithValue(
            _FakePermissionService(AudioPermissionStatus.notRequested),
          ),
        ],
        child: const VibyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Empty-library welcome + all four bottom-nav destinations.
    expect(find.text('Welcome to Viby'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    // First-run call-to-action (access, not a manual scan button).
    expect(find.text('Allow access'), findsOneWidget);
    expect(find.text('Scan library'), findsNothing);
  });
}
