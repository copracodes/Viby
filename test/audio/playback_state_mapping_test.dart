// Unit tests for the pure just_audio -> audio_service PlaybackState mapping
// that drives the notification / lock screen. No player, no plugins involved.

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:viby/audio/audio_handler.dart';

void main() {
  group('buildPlaybackState', () {
    test('maps every just_audio ProcessingState to its audio_service peer', () {
      const Map<ProcessingState, AudioProcessingState> expected =
          <ProcessingState, AudioProcessingState>{
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          };

      expected.forEach((ProcessingState input, AudioProcessingState want) {
        final PlaybackState state = buildPlaybackState(
          playing: false,
          processingState: input,
          position: Duration.zero,
          bufferedPosition: Duration.zero,
          speed: 1.0,
        );
        expect(state.processingState, want, reason: '$input');
      });
    });

    test('exposes a pause control (not play) and playing=true when playing', () {
      final PlaybackState state = buildPlaybackState(
        playing: true,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 5),
        bufferedPosition: const Duration(seconds: 10),
        speed: 1.0,
      );

      expect(state.playing, isTrue);
      expect(state.controls, contains(MediaControl.pause));
      expect(state.controls, isNot(contains(MediaControl.play)));
    });

    test('exposes a play control (not pause) and playing=false when paused', () {
      final PlaybackState state = buildPlaybackState(
        playing: false,
        processingState: ProcessingState.ready,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      );

      expect(state.playing, isFalse);
      expect(state.controls, contains(MediaControl.play));
      expect(state.controls, isNot(contains(MediaControl.pause)));
    });

    test('forwards position, buffered position and speed verbatim', () {
      final PlaybackState state = buildPlaybackState(
        playing: true,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 3),
        bufferedPosition: const Duration(seconds: 8),
        speed: 1.5,
        queueIndex: 0,
      );

      expect(state.updatePosition, const Duration(seconds: 3));
      expect(state.bufferedPosition, const Duration(seconds: 8));
      expect(state.speed, 1.5);
      expect(state.queueIndex, 0);
    });

    test('compact action indices map to previous / play-pause / next', () {
      final PlaybackState state = buildPlaybackState(
        playing: false,
        processingState: ProcessingState.ready,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      );

      expect(state.androidCompactActionIndices, <int>[0, 1, 3]);
      // controls: [skipToPrevious, play/pause, stop, skipToNext]
      expect(state.controls.first, MediaControl.skipToPrevious);
      expect(state.controls.last, MediaControl.skipToNext);
    });
  });
}
