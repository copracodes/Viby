import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/db/daos/library_dao.dart';
import 'package:viby/data/db/tables.dart' show TrackSource, TrackVisibility;
import 'package:viby/data/db/viby_database.dart';
import 'package:viby/data/sources/local/media_delete_channel.dart';
import 'package:viby/state/library_providers.dart';
import 'package:viby/ui/theme/app_theme.dart';
import 'package:viby/ui/widgets/track_actions_sheet.dart';

/// A deleter whose capability the test controls, recording what it was asked to
/// delete.
class _FakeDeleter implements MediaDeleter {
  _FakeDeleter({this.capable = true});

  @override
  final bool capable;
  final List<int> requested = <int>[];
  DeleteOutcome outcome = DeleteOutcome.granted;

  /// Stands in for an API 30+ device: the system shows the confirmation.
  @override
  Future<bool> systemConfirms() async => true;

  @override
  Future<DeleteOutcome> deleteTracks({
    required List<int> mediaIds,
    required List<String?> paths,
  }) async {
    requested.addAll(mediaIds);
    return outcome;
  }
}

TrackRow _row(String id, {TrackSource source = TrackSource.local}) => TrackRow(
      id: id,
      source: source,
      title: 'Song $id',
      albumId: 'album:1',
      artistId: 'artist:1',
      trackNo: 1,
      discNo: 0,
      durationMs: 180000,
      filePath: '/music/$id.mp3',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
      playable: true,
      visibility: TrackVisibility.visible,
      userOverride: false,
      liked: false,
    );

/// Mounts a button that opens the track-actions sheet for [row].
Future<void> _openSheet(
  WidgetTester tester,
  TrackRow row,
  MediaDeleter deleter,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mediaDeleterProvider.overrideWithValue(deleter),
        trackLikedProvider(row.id).overrideWith((Ref ref) => Stream<bool>.value(false)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTrackActions(
                  context,
                  ref,
                  TrackWithMeta(track: row, artistName: 'The Band'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet offers Delete alongside Hide, in the error colour',
      (WidgetTester tester) async {
    await _openSheet(tester, _row('local:7'), _FakeDeleter());

    expect(find.text('Hide song'), findsOneWidget);
    expect(find.text('Keeps the file on your device'), findsOneWidget);
    expect(find.text('Delete from device'), findsOneWidget);
    expect(find.text('Removes the file permanently'), findsOneWidget);

    // The destructive row must LOOK destructive — the two sit next to each other.
    final BuildContext context = tester.element(find.text('Delete from device'));
    final Color error = Theme.of(context).colorScheme.error;
    final Icon icon = tester.widget<Icon>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Delete from device'),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    expect(icon.color, error);
  });

  testWidgets('a Subsonic track cannot be deleted from the device',
      (WidgetTester tester) async {
    await _openSheet(
      tester,
      _row('subsonic:s1:7', source: TrackSource.subsonic),
      _FakeDeleter(),
    );

    expect(find.text('Hide song'), findsOneWidget);
    expect(find.text('Delete from device'), findsNothing);
  });

  testWidgets('the action is absent where the platform cannot delete',
      (WidgetTester tester) async {
    await _openSheet(tester, _row('local:7'), _FakeDeleter(capable: false));

    expect(find.text('Hide song'), findsOneWidget);
    expect(find.text('Delete from device'), findsNothing);
  });
}
