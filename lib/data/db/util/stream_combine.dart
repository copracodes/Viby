import 'dart:async';

/// Emits a combined value whenever *either* source stream emits, using the most
/// recent value from each. Nothing is emitted until both have produced at least
/// one value.
///
/// A tiny stand-in for `rxdart`'s `combineLatest2` so the DAOs can compose two
/// drift `watch()` streams (e.g. a parent row + its children) without adding a
/// dependency.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> streamA,
  Stream<B> streamB,
  R Function(A a, B b) combine,
) {
  final StreamController<R> controller = StreamController<R>();
  late A latestA;
  late B latestB;
  bool hasA = false;
  bool hasB = false;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;

  void emit() {
    if (hasA && hasB) controller.add(combine(latestA, latestB));
  }

  controller.onListen = () {
    subA = streamA.listen(
      (A value) {
        latestA = value;
        hasA = true;
        emit();
      },
      onError: controller.addError,
    );
    subB = streamB.listen(
      (B value) {
        latestB = value;
        hasB = true;
        emit();
      },
      onError: controller.addError,
    );
  };
  controller.onCancel = () async {
    await subA?.cancel();
    await subB?.cancel();
  };

  return controller.stream;
}
