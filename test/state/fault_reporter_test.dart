import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/playback_fault.dart';
import 'package:viby/state/fault_reporter.dart';

void main() {
  test('marks the track unplayable and messages "skipped"', () {
    final List<String> marked = <String>[];
    final List<String> messages = <String>[];
    final FaultReporter reporter = FaultReporter(
      markUnplayable: (String id) async => marked.add(id),
      showMessage: messages.add,
    );

    reporter.onFault(const PlaybackFault(
      trackId: 'local:7',
      title: 'Broken Song',
      allFailed: false,
    ));

    expect(marked, <String>['local:7']);
    expect(messages.single, contains('Broken Song'));
    expect(messages.single, contains('skipped'));
  });

  test('uses the terminal message when the whole queue failed', () {
    final List<String> messages = <String>[];
    final FaultReporter reporter = FaultReporter(
      markUnplayable: (_) async {},
      showMessage: messages.add,
    );

    reporter.onFault(const PlaybackFault(
      trackId: 'local:1',
      title: 'Song',
      allFailed: true,
    ));

    expect(messages.single, contains('nothing else in the queue'));
  });

  test('handles a null track id / title gracefully', () {
    final List<String> marked = <String>[];
    final List<String> messages = <String>[];
    final FaultReporter reporter = FaultReporter(
      markUnplayable: (String id) async => marked.add(id),
      showMessage: messages.add,
    );

    reporter.onFault(
      const PlaybackFault(trackId: null, title: null, allFailed: false),
    );

    expect(marked, isEmpty); // nothing to mark
    expect(messages.single, contains('this track'));
  });
}
