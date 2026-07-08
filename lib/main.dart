import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'audio/audio_handler.dart';
import 'audio/eq_service.dart';
import 'audio/player_service.dart';
import 'core/perf.dart';
import 'state/eq_providers.dart';
import 'state/player_providers.dart';

Future<void> main() async {
  // Touch the cold-start stopwatch first so time-to-first-frame is measured
  // from as early as possible (the field starts the watch on init).
  coldStartWatch;
  WidgetsFlutterBinding.ensureInitialized();

  // Deliberate image-cache budget. Art is decoded downsampled (see
  // AlbumArt.cacheWidth), so a 120 MB / 600-entry cap holds a large scroll's
  // worth of thumbnails plus the full-res Now Playing art without unbounded
  // growth over a long browsing session.
  final ImageCache imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSizeBytes = 120 << 20; // 120 MB
  imageCache.maximumSize = 600; // entries

  // Profile-only frame-jank logging (no-op in release).
  installFrameMonitor();

  // Build the equalizer effects *before* the player — an AudioPipeline must be
  // attached at player construction. Capability-gated: a no-op engine on
  // platforms without EQ support (see EqEngine.build / CLAUDE.md).
  final EqEngine eqEngine = EqEngine.build();

  // Start the audio_service isolate/session and get back our handler. This
  // wires the OS media session (notification, lock screen, media buttons).
  final VibyAudioHandler handler = await AudioService.init(
    builder: () => VibyAudioHandler(eqEngine: eqEngine),
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
        eqEngineProvider.overrideWithValue(eqEngine),
      ],
      child: const VibyApp(),
    ),
  );
}
