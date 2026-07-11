import 'package:flutter/services.dart';

/// Whether the current network is unmetered (Wi-Fi / Ethernet) — gates the
/// "Wi-Fi only" online-lyrics setting. Abstracted for testability.
abstract interface class NetworkProbe {
  Future<bool> isUnmetered();
}

/// Default probe over a native `ConnectivityManager` check (`MainActivity`'s
/// `com.copra.viby/connectivity` channel) — no third-party dependency. Fail-open
/// (returns true) on any error / off-Android, since online-lyrics payloads are
/// tiny and blocking on a probe failure would be worse than a rare metered fetch.
class PlatformNetworkProbe implements NetworkProbe {
  const PlatformNetworkProbe();

  static const MethodChannel _channel =
      MethodChannel('com.copra.viby/connectivity');

  @override
  Future<bool> isUnmetered() async {
    try {
      final bool? unmetered =
          await _channel.invokeMethod<bool>('isUnmetered');
      return unmetered ?? true;
    } catch (_) {
      return true;
    }
  }
}
