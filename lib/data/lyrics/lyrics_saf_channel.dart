import 'package:flutter/services.dart';

/// The platform bridge for Storage Access Framework lyrics reads. Abstracted so
/// [SafSidecarSource] and the folder-grant flow are unit-testable with a fake.
///
/// A `.lrc` sidecar is a non-media file; scoped storage on Android 13+ blocks a
/// bare `File()` read (EACCES). The user grants a folder once via
/// `ACTION_OPEN_DOCUMENT_TREE` (a persistable tree URI) and sidecars are read
/// through SAF — no broad storage permission.
abstract interface class LyricsSafBridge {
  /// Launches the system folder picker; returns the granted tree URI (persisted
  /// natively) or null if the user cancelled.
  Future<String?> pickFolder();

  /// Whether [treeUri] is still a persisted, readable grant.
  Future<bool> hasAccess(String treeUri);

  /// Reads a sidecar under [treeUri]: the same-directory `.lrc` at [absPath], or
  /// `<grantedRoot>/Lyrics/<sidecarName>`. Returns the bytes or null.
  Future<Uint8List?> readSidecar({
    required String treeUri,
    required String absPath,
    required String sidecarName,
  });
}

/// The real bridge over the `com.copra.viby/lyrics_saf` [MethodChannel]
/// (implemented in `MainActivity.kt`). No-ops off Android (invokeMethod throws
/// `MissingPluginException`, which the callers treat as "no access").
class PlatformLyricsSafBridge implements LyricsSafBridge {
  const PlatformLyricsSafBridge();

  static const MethodChannel _channel =
      MethodChannel('com.copra.viby/lyrics_saf');

  @override
  Future<String?> pickFolder() => _channel.invokeMethod<String>('pickFolder');

  @override
  Future<bool> hasAccess(String treeUri) async {
    final bool? ok = await _channel.invokeMethod<bool>(
      'hasAccess',
      <String, String>{'treeUri': treeUri},
    );
    return ok ?? false;
  }

  @override
  Future<Uint8List?> readSidecar({
    required String treeUri,
    required String absPath,
    required String sidecarName,
  }) {
    return _channel.invokeMethod<Uint8List>('readSidecar', <String, String>{
      'treeUri': treeUri,
      'absPath': absPath,
      'sidecarName': sidecarName,
    });
  }
}
