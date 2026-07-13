import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/player_service.dart';
import '../audio/replay_gain.dart';
import '../audio/sleep_timer.dart';
import '../data/db/daos/preferences_dao.dart';
import 'database_providers.dart';
import 'player_providers.dart';

part 'playback_providers.g.dart';

/// Preference keys (the v4 KV store — playback settings are preferences, not
/// schema, so none of this needs a migration).
const String _kRgMode = 'rg_mode';
const String _kRgPreamp = 'rg_preamp_db';
const String _kRgPreventClipping = 'rg_prevent_clipping';
const String _kSkipSilence = 'skip_silence';

/// Everything under Settings › Playback that survives a restart.
class PlaybackSettings {
  const PlaybackSettings({
    this.replayGain = const ReplayGainSettings(),
    this.skipSilence = false,
  });

  final ReplayGainSettings replayGain;
  final bool skipSilence;

  PlaybackSettings copyWith({
    ReplayGainSettings? replayGain,
    bool? skipSilence,
  }) =>
      PlaybackSettings(
        replayGain: replayGain ?? this.replayGain,
        skipSilence: skipSilence ?? this.skipSilence,
      );
}

/// Persisted playback settings, pushed into the audio layer on every change.
///
/// keepAlive: these are app-wide, and the player must keep obeying them with no
/// Settings screen mounted.
@Riverpod(keepAlive: true)
class PlaybackSettingsController extends _$PlaybackSettingsController {
  @override
  PlaybackSettings build() {
    // Defaults first (so the first frame is correct), then hydrate from drift
    // and push the real values down to the player.
    Future<void>(_hydrate);
    return const PlaybackSettings();
  }

  Future<void> _hydrate() async {
    final PreferencesDao dao = ref.read(vibyDatabaseProvider).preferencesDao;
    final String? mode = await dao.get(_kRgMode);
    final String? preamp = await dao.get(_kRgPreamp);
    final String? clip = await dao.get(_kRgPreventClipping);
    final String? silence = await dao.get(_kSkipSilence);

    state = PlaybackSettings(
      replayGain: ReplayGainSettings(
        mode: ReplayGainMode.values.firstWhere(
          (ReplayGainMode m) => m.name == mode,
          orElse: () => ReplayGainMode.off,
        ),
        preampDb: double.tryParse(preamp ?? '') ?? 0,
        preventClipping: clip == null ? true : clip == 'true',
      ),
      skipSilence: silence == 'true',
    );
    await _push();
  }

  /// One place that talks to the player, so no setter can forget to.
  Future<void> _push() async {
    final PlayerService player = ref.read(playerServiceProvider);
    await player.setReplayGainSettings(state.replayGain);
    await player.setSkipSilenceEnabled(state.skipSilence);
  }

  Future<void> setMode(ReplayGainMode mode) async {
    state = state.copyWith(replayGain: state.replayGain.copyWith(mode: mode));
    await ref.read(vibyDatabaseProvider).preferencesDao.set(_kRgMode, mode.name);
    await _push();
  }

  Future<void> setPreamp(double db) async {
    final double clamped = db.clamp(kPreampMinDb, kPreampMaxDb);
    state =
        state.copyWith(replayGain: state.replayGain.copyWith(preampDb: clamped));
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_kRgPreamp, clamped.toString());
    await _push();
  }

  Future<void> setPreventClipping(bool value) async {
    state = state.copyWith(
      replayGain: state.replayGain.copyWith(preventClipping: value),
    );
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_kRgPreventClipping, value.toString());
    await _push();
  }

  Future<void> setSkipSilence(bool value) async {
    state = state.copyWith(skipSilence: value);
    await ref
        .read(vibyDatabaseProvider)
        .preferencesDao
        .set(_kSkipSilence, value.toString());
    await _push();
  }
}

/// The sleep timer's live state (armed mode + countdown), straight from the
/// audio layer — so a rebuilt UI just re-reads it and a backgrounded app keeps
/// counting.
@riverpod
Stream<SleepTimerState> sleepTimer(Ref ref) =>
    ref.watch(playerServiceProvider).sleepTimer;

/// Playback speed. Deliberately **session-only**: it is NOT persisted, and
/// resets to 1.0x on app restart.
///
/// Speed is a per-listening-session decision (this podcast, right now), not a
/// preference. A persisted 1.5x is a trap: you set it for an audiobook, come back
/// tomorrow, play music, and everything is subtly wrong in a way that's very hard
/// to attribute to a setting you forgot you set — so we let a restart clear it.
@riverpod
Stream<double> playbackSpeed(Ref ref) =>
    ref.watch(playerServiceProvider).speed;

/// The speeds the stepper offers.
const List<double> kSpeedPresets = <double>[
  0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
];

const double kSpeedMin = 0.5;
const double kSpeedMax = 2.0;
