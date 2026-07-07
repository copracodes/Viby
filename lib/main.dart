import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'audio/player_service.dart';
import 'state/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Give the album-art thumbnail cache headroom for scrolling a large library
  // (10k tracks). Art is decoded downsampled (see AlbumArt.cacheWidth), so this
  // holds many thumbnails without ballooning memory.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20; // 160 MB

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
