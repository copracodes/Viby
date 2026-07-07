import 'package:flutter/material.dart';

/// App-wide [ScaffoldMessenger] key, wired on `MaterialApp.router`, so
/// non-widget code (e.g. the playback fault reporter) can surface a SnackBar
/// without a [BuildContext].
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
