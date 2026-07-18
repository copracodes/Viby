import 'package:flutter/services.dart';

/// Central, subtle system haptics. All feedback routes through here so it can be
/// tuned — and globally switched off (Settings) — in one place.
///
/// Policy (Step 2.3): [light] on play/pause, skip commit, queue reorder drop,
/// playlist add; [selection] on shuffle/repeat toggle; **nothing** on scrolling
/// or drag-follow (those would buzz constantly).
class HapticsService {
  HapticsService(this._enabled);

  final bool Function() _enabled;

  /// A light impact — discrete, committed actions.
  void light() {
    if (_enabled()) HapticFeedback.lightImpact();
  }

  /// A selection tick — toggling a mode.
  void selection() {
    if (_enabled()) HapticFeedback.selectionClick();
  }

  /// A firmer buzz — a rejected action (e.g. an invalid A–B loop end).
  void reject() {
    if (_enabled()) HapticFeedback.heavyImpact();
  }
}
