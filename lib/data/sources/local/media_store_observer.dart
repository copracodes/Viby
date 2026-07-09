import 'dart:async';

import 'package:flutter/services.dart';

/// The EventChannel bridged from the native [ContentObserver] in MainActivity —
/// must match `MEDIA_OBSERVER_CHANNEL` there.
const String kMediaObserverChannel = 'com.copra.viby/media_observer';

/// Wraps the native MediaStore change notifications as a Dart stream of ticks.
///
/// `on_audio_query` is pull-only, so change detection is bridged natively: the
/// Activity registers a `ContentObserver` on the audio content URI and forwards
/// each `onChange` over an EventChannel. Each event is a bare "something
/// changed" tick (no payload) — the listener debounces and runs an incremental
/// rescan. On non-Android platforms the channel simply never emits.
class MediaStoreObserver {
  MediaStoreObserver({EventChannel? channel})
      : _channel = channel ?? const EventChannel(kMediaObserverChannel);

  final EventChannel _channel;

  /// A tick each time MediaStore audio changes (added / removed / edited).
  Stream<void> changes() =>
      _channel.receiveBroadcastStream().map<void>((Object? _) {});
}

/// Coalesces a burst of rapid pings into a single fire after a quiet [delay].
///
/// Downloads and media syncs fire many `onChange` ticks in quick succession; the
/// debouncer waits for the storm to settle before triggering one rescan. Pure
/// timer logic — drive it with `fakeAsync` in tests.
class ScanDebouncer {
  ScanDebouncer(this.delay, this._onFire);

  final Duration delay;
  final void Function() _onFire;
  Timer? _timer;

  /// Registers activity; (re)starts the quiet-period countdown.
  void ping() {
    _timer?.cancel();
    _timer = Timer(delay, _onFire);
  }

  /// Cancels any pending fire.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
