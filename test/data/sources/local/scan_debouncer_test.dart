import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/sources/local/media_store_observer.dart';

void main() {
  group('ScanDebouncer', () {
    test('a burst of pings fires exactly once, after the quiet delay', () {
      fakeAsync((FakeAsync async) {
        int fired = 0;
        final ScanDebouncer d =
            ScanDebouncer(const Duration(seconds: 3), () => fired++);

        // Rapid burst (a download): 5 pings within 1s.
        for (int i = 0; i < 5; i++) {
          d.ping();
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(fired, 0, reason: 'still within the quiet period');

        async.elapse(const Duration(seconds: 3));
        expect(fired, 1, reason: 'fires once after the storm settles');

        d.dispose();
      });
    });

    test('separated pings fire once each', () {
      fakeAsync((FakeAsync async) {
        int fired = 0;
        final ScanDebouncer d =
            ScanDebouncer(const Duration(seconds: 3), () => fired++);

        d.ping();
        async.elapse(const Duration(seconds: 4));
        expect(fired, 1);

        d.ping();
        async.elapse(const Duration(seconds: 4));
        expect(fired, 2);

        d.dispose();
      });
    });

    test('dispose cancels a pending fire', () {
      fakeAsync((FakeAsync async) {
        int fired = 0;
        final ScanDebouncer d =
            ScanDebouncer(const Duration(seconds: 3), () => fired++);
        d.ping();
        d.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(fired, 0);
      });
    });
  });
}
