import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Toast severity levels.
enum ToastKind { success, warning, error, info }

/// Thin facade over forui's [FToaster] / [showFToast].
///
/// Usage:
/// ```dart
/// AppMessenger.show(context, ToastKind.success, 'Saved');
/// ```
///
/// Call [AppMessenger.init] once in the [MaterialApp.builder] to install
/// the toaster host. Then use [AppMessenger.show] from anywhere.
class AppMessenger {
  AppMessenger._();

  static final AppMessenger _instance = AppMessenger._();
  static AppMessenger get instance => _instance;

  /// Cached toaster state — set on first [show] call with a valid context
  /// or via [cacheOverlay]. Survives after the originating context has
  /// been popped so optimistic-form failures can still surface.
  FToasterState? _cachedToaster;

  /// Install the toaster host. Call in [MaterialApp.builder].
  static Widget init({required Widget child}) =>
      _ToasterHost(child: FToaster(child: child));

  /// Cache the surrounding [FToaster] state so that [show] can post toasts
  /// even after the calling [context] is unmounted (e.g. after a pop).
  static void cacheOverlay(BuildContext context) {
    try {
      _instance._cachedToaster ??= context
          .findAncestorStateOfType<FToasterState>();
    } catch (_) {
      // Context may already be unmounted.
    }
  }

  /// Show a toast.
  static void show(
    BuildContext context,
    ToastKind kind,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _instance._show(context, kind, message, duration, actionLabel, onAction);
  }

  void _show(
    BuildContext context,
    ToastKind kind,
    String message,
    Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    FToasterState? state;
    try {
      state = context.findAncestorStateOfType<FToasterState>();
    } catch (_) {
      // Context may be unmounted after a Navigator.pop.
    }
    state ??= _cachedToaster;
    if (state == null) return;
    _cachedToaster = state;

    final variant = switch (kind) {
      ToastKind.error => FToastVariant.destructive,
      ToastKind.warning => FToastVariant.destructive,
      ToastKind.success => FToastVariant.primary,
      ToastKind.info => FToastVariant.primary,
    };
    final icon = Icon(switch (kind) {
      ToastKind.success => Icons.check_circle_outline_rounded,
      ToastKind.warning => Icons.warning_amber_rounded,
      ToastKind.error => Icons.error_outline_rounded,
      ToastKind.info => Icons.info_outline_rounded,
    });

    state.show(
      context: context,
      builder: (ctx, entry) => FToast(
        variant: variant,
        icon: icon,
        title: Text(message),
        suffix: actionLabel != null && onAction != null
            ? FButton(
                variant: FButtonVariant.ghost,
                onPress: () {
                  onAction();
                  entry.dismiss();
                },
                child: Text(actionLabel),
              )
            : null,
      ),
      duration: duration,
    );
  }
}

class _ToasterHost extends StatefulWidget {
  const _ToasterHost({required this.child});

  final Widget child;

  @override
  State<_ToasterHost> createState() => _ToasterHostState();
}

class _ToasterHostState extends State<_ToasterHost> {
  @override
  void dispose() {
    AppMessenger._instance._cachedToaster = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
