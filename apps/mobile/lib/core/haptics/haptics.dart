import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralised haptic feedback for the app.
///
/// Each method maps a UX intent (primary press, selection change, destructive
/// confirm, success, error) to the right [HapticFeedback] level — so call
/// sites express *what just happened* rather than *which impact strength*.
///
/// Only fires on iOS / Android. Web and desktop are no-ops because the
/// underlying platform channel either isn't wired up or produces no perceptible
/// feedback. Centralising here also gives us a single seam for a future
/// "disable haptics" user preference and for silencing haptics in widget tests
/// where the platform channel mock isn't installed.
class Haptics {
  Haptics._();

  /// Test seam — when true, every method is a no-op regardless of platform.
  /// Widget tests should set this to true in `setUpAll` so they don't blow
  /// up on the un-mocked `SystemChannels.platform` invocation.
  @visibleForTesting
  static bool disabled = false;

  static bool get isEnabled {
    if (disabled) return false;
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Primary action pressed — FAB, primary button, AI propose confirm.
  static void primaryPress() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.lightImpact());
  }

  /// Selection changed — ChoiceChip, Tab, SegmentedButton, long-press drag pickup.
  static void selection() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.selectionClick());
  }

  /// Destructive action committed — list item dismissed / deleted.
  static void destructive() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.mediumImpact());
  }

  /// Form / async action succeeded.
  static void success() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.lightImpact());
  }

  /// Form / async action failed (error toast / SnackBar).
  static void error() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.heavyImpact());
  }

  /// Wraps a `VoidCallback` so it fires [primaryPress] before invoking the
  /// inner callback. Returns null when given null, so it composes with the
  /// `onPressed: ...` style used by Flutter buttons.
  static VoidCallback? wrapPrimary(VoidCallback? cb) {
    if (cb == null) return null;
    return () {
      primaryPress();
      cb();
    };
  }
}
