import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

/// Coarse permission state the UI gates on.
enum AudioPermissionStatus {
  /// Never asked yet — show a rationale before the system prompt.
  notRequested,

  /// Granted (or limited) — the scanner may run.
  granted,

  /// Denied but can be re-requested.
  denied,

  /// Denied with "don't ask again" — must be fixed in system settings.
  permanentlyDenied,
}

/// Wraps the runtime-permission flow for reading on-device audio.
///
/// Picks the permission set for the OS version: on Android 13+/API 33 this is
/// READ_MEDIA_AUDIO **and** READ_MEDIA_IMAGES (the on_audio_query_pluse fork
/// gates its queries on both — see AndroidManifest); on API ≤ 32 it's
/// READ_EXTERNAL_STORAGE. The device SDK level comes from on_audio_query, so no
/// extra device-info dependency is needed.
class AudioPermissionService {
  AudioPermissionService(this._audioQuery);

  final OnAudioQuery _audioQuery;

  Future<List<Permission>> _permissions() async {
    final DeviceModel device = await _audioQuery.queryDeviceInfo();
    if (device.version >= 33) {
      return <Permission>[Permission.audio, Permission.photos];
    }
    return <Permission>[Permission.storage];
  }

  Future<AudioPermissionStatus> check() async {
    final List<Permission> permissions = await _permissions();
    final List<PermissionStatus> statuses = <PermissionStatus>[];
    bool anyRationale = false;
    for (final Permission permission in permissions) {
      statuses.add(await permission.status);
      if (await permission.shouldShowRequestRationale) anyRationale = true;
    }
    return _combine(statuses, anyRationale);
  }

  Future<AudioPermissionStatus> request() async {
    final List<Permission> permissions = await _permissions();
    final Map<Permission, PermissionStatus> results = await permissions.request();
    bool anyRationale = false;
    for (final Permission permission in permissions) {
      if (await permission.shouldShowRequestRationale) anyRationale = true;
    }
    return _combine(results.values.toList(), anyRationale);
  }

  /// Opens the system app-settings page (for the permanently-denied case).
  Future<bool> openSettings() => openAppSettings();

  /// Granted only when **every** required permission is granted; a single
  /// permanent denial is surfaced as permanently-denied so the UI shows the
  /// settings path.
  AudioPermissionStatus _combine(
    List<PermissionStatus> statuses,
    bool anyRationale,
  ) {
    if (statuses.every((PermissionStatus s) => s.isGranted || s.isLimited)) {
      return AudioPermissionStatus.granted;
    }
    if (statuses.any((PermissionStatus s) => s.isPermanentlyDenied)) {
      return AudioPermissionStatus.permanentlyDenied;
    }
    // On Android a first-time (never-asked) permission also reports as denied;
    // `shouldShowRequestRationale` only becomes true after one denial, which
    // separates never-asked from actively-denied.
    if (statuses.any((PermissionStatus s) => s.isDenied)) {
      return anyRationale
          ? AudioPermissionStatus.denied
          : AudioPermissionStatus.notRequested;
    }
    return AudioPermissionStatus.notRequested;
  }
}
