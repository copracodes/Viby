import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'audio/player_service.dart';
import 'state/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the audio_service isolate/session and get back our handler. This
  // wires the OS media session (notification, lock screen, media buttons).
  final VibyAudioHandler handler = await AudioService.init(
    builder: VibyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.copra.viby.playback',
      androidNotificationChannelName: 'Viby playback',
      // Keep the notification/session alive while paused, but drop the
      // foreground status so it can be swiped away when not playing.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Monochrome status-bar icon (res/drawable/ic_stat_viby.xml).
      androidNotificationIcon: 'drawable/ic_stat_viby',
    ),
  );

  final PlayerService playerService = PlayerService(handler);

  runApp(
    ProviderScope(
      overrides: <Override>[
        playerServiceProvider.overrideWithValue(playerService),
      ],
      child: const VibyApp(),
    ),
  );
}
