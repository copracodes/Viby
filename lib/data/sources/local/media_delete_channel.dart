import 'dart:io';

import 'package:flutter/services.dart';

/// The MethodChannel bridged from MainActivity — must match
/// `MEDIA_DELETE_CHANNEL` there.
const String kMediaDeleteChannel = 'com.copra.viby/media_delete';

/// The Android API level from which [MediaStore.createDeleteRequest] exists and
/// direct file deletion is forbidden (Android 11 / R).
const int kDeleteRequestApiLevel = 30;

/// Outcome of a delete request. Mirrors the strings the native side returns.
///
/// [granted] means the files are *gone* (the user approved the system dialog, or
/// the legacy path deleted them) — only then may the library be purged.
/// [denied] is a user decline: a silent no-op. [failed] is an honest error
/// (read-only card, locked file): report it, change nothing.
enum DeleteOutcome { granted, denied, failed }

DeleteOutcome _outcomeFrom(String? raw) => switch (raw) {
      'granted' => DeleteOutcome.granted,
      'denied' => DeleteOutcome.denied,
      _ => DeleteOutcome.failed,
    };

/// Permanently deletes audio files from the device.
///
/// Platform capability behind one interface (CLAUDE.md rule 6): Android gets
/// [PlatformMediaDeleter]; everywhere else [NoopMediaDeleter] reports
/// `capable == false` so callers never branch on `Platform`.
abstract interface class MediaDeleter {
  /// Whether this device can delete files at all (false = the UI hides the
  /// action entirely).
  bool get capable;

  /// True when the platform shows its OWN delete confirmation (API 30+), so the
  /// app must not stack a second dialog on top for a single track.
  Future<bool> systemConfirms();

  /// Deletes the given MediaStore entries. [mediaIds] are MediaStore row ids;
  /// [paths] are the matching absolute file paths (index-aligned, used only on
  /// the legacy path). One request covers the whole batch.
  Future<DeleteOutcome> deleteTracks({
    required List<int> mediaIds,
    required List<String?> paths,
  });
}

/// Android implementation, over the `media_delete` MethodChannel.
class PlatformMediaDeleter implements MediaDeleter {
  PlatformMediaDeleter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kMediaDeleteChannel);

  final MethodChannel _channel;
  int? _apiLevel;

  @override
  bool get capable => true;

  @override
  Future<bool> systemConfirms() async {
    final int level = _apiLevel ??=
        await _channel.invokeMethod<int>('apiLevel') ?? kDeleteRequestApiLevel;
    return level >= kDeleteRequestApiLevel;
  }

  @override
  Future<DeleteOutcome> deleteTracks({
    required List<int> mediaIds,
    required List<String?> paths,
  }) async {
    if (mediaIds.isEmpty) return DeleteOutcome.granted;
    try {
      final String? raw = await _channel.invokeMethod<String>(
        'deleteTracks',
        <String, Object?>{'mediaIds': mediaIds, 'paths': paths},
      );
      return _outcomeFrom(raw);
    } on PlatformException {
      return DeleteOutcome.failed;
    } on MissingPluginException {
      return DeleteOutcome.failed;
    }
  }
}

/// The no-op implementation used off Android: deletion is never offered.
class NoopMediaDeleter implements MediaDeleter {
  const NoopMediaDeleter();

  @override
  bool get capable => false;

  @override
  Future<bool> systemConfirms() async => false;

  @override
  Future<DeleteOutcome> deleteTracks({
    required List<int> mediaIds,
    required List<String?> paths,
  }) async =>
      DeleteOutcome.failed;
}

/// Builds the capable deleter on Android and the no-op one elsewhere.
MediaDeleter buildMediaDeleter() =>
    Platform.isAndroid ? PlatformMediaDeleter() : const NoopMediaDeleter();
