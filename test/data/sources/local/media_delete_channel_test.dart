import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/sources/local/media_delete_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(kMediaDeleteChannel);
  final List<MethodCall> calls = <MethodCall>[];

  /// Stands in for MainActivity: records the call and replies [reply].
  void mockNative({Object? reply, int apiLevel = 34, bool throwError = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'apiLevel') return apiLevel;
      if (throwError) {
        throw PlatformException(code: 'busy');
      }
      return reply;
    });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PlatformMediaDeleter', () {
    test('maps the native reply onto the outcome', () async {
      for (final (String raw, DeleteOutcome expected) in <(String, DeleteOutcome)>[
        ('granted', DeleteOutcome.granted),
        ('denied', DeleteOutcome.denied),
        ('failed', DeleteOutcome.failed),
      ]) {
        mockNative(reply: raw);
        final DeleteOutcome outcome = await PlatformMediaDeleter()
            .deleteTracks(mediaIds: <int>[1], paths: <String?>['/a.mp3']);
        expect(outcome, expected, reason: raw);
      }
    });

    test('an unknown or missing reply is a failure, never a success', () async {
      mockNative(reply: null);
      expect(
        await PlatformMediaDeleter()
            .deleteTracks(mediaIds: <int>[1], paths: <String?>[null]),
        DeleteOutcome.failed,
      );
    });

    test('a platform exception is a failure (no partial DB cleanup)', () async {
      mockNative(throwError: true);
      expect(
        await PlatformMediaDeleter()
            .deleteTracks(mediaIds: <int>[1], paths: <String?>[null]),
        DeleteOutcome.failed,
      );
    });

    test('sends the whole batch in ONE request (one system dialog)', () async {
      mockNative(reply: 'granted');
      await PlatformMediaDeleter().deleteTracks(
        mediaIds: <int>[1, 2, 3],
        paths: <String?>['/a.mp3', '/b.mp3', '/c.mp3'],
      );

      expect(calls.length, 1);
      expect(calls.single.method, 'deleteTracks');
      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(args['mediaIds'], <int>[1, 2, 3]);
    });

    test('an empty selection never reaches the platform', () async {
      mockNative(reply: 'granted');
      expect(
        await PlatformMediaDeleter()
            .deleteTracks(mediaIds: <int>[], paths: <String?>[]),
        DeleteOutcome.granted,
      );
      expect(calls, isEmpty);
    });

    test('the system confirms from API 30, and not below', () async {
      mockNative(apiLevel: 34);
      expect(await PlatformMediaDeleter().systemConfirms(), isTrue);

      mockNative(apiLevel: 29);
      expect(await PlatformMediaDeleter().systemConfirms(), isFalse);
    });
  });

  group('NoopMediaDeleter', () {
    test('is incapable, so the delete action is never offered', () async {
      const NoopMediaDeleter deleter = NoopMediaDeleter();
      expect(deleter.capable, isFalse);
      expect(await deleter.systemConfirms(), isFalse);
      expect(
        await deleter.deleteTracks(mediaIds: <int>[1], paths: <String?>[null]),
        DeleteOutcome.failed,
      );
    });
  });
}
