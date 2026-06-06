import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/haptics/haptics.dart';
import '../theme/semantic_colors.dart';
import '../tokens/dimens_tokens.dart';

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
    var usingCachedState = false;
    try {
      state = context.findAncestorStateOfType<FToasterState>();
    } catch (_) {
      // Context may be unmounted after a Navigator.pop.
    }
    if (state == null) {
      state = _cachedToaster;
      usingCachedState = true;
    }
    if (state == null) return;
    _cachedToaster = state;

    // Fire haptic feedback matching the toast severity.
    switch (kind) {
      case ToastKind.success:
        Haptics.success();
      case ToastKind.error:
        Haptics.error();
      case ToastKind.warning:
      case ToastKind.info:
        break;
    }

    state.show(
      context: usingCachedState ? null : context,
      builder: (ctx, entry) => _AppToastSurface(
        kind: kind,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                onAction();
                entry.dismiss();
              },
      ),
      duration: duration,
    );
  }
}

class _AppToastSurface extends StatelessWidget {
  const _AppToastSurface({
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final ToastKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final palette = _ToastPalette.resolve(context, kind);
    final isDark = colors.brightness == Brightness.dark;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(
      420.0,
      math.max(AppSpacing.s64, viewportWidth - AppSpacing.s32),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.container.withValues(alpha: isDark ? 0.55 : 0.72),
            colors.background,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: palette.accent.withValues(alpha: isDark ? 0.34 : 0.26),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(
                alpha: isDark ? AppOpacity.muted : AppOpacity.faint,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(palette.icon, color: palette.accent, size: AppIconSizes.md),
              const SizedBox(width: AppSpacing.s10),
              Flexible(
                child: Text(
                  message,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: onAction,
                  child: Text(
                    actionLabel!,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastPalette {
  const _ToastPalette({
    required this.accent,
    required this.container,
    required this.icon,
  });

  final Color accent;
  final Color container;
  final IconData icon;

  static _ToastPalette resolve(BuildContext context, ToastKind kind) {
    final semantic = SemanticColors.of(context);
    return switch (kind) {
      ToastKind.success => _ToastPalette(
        accent: semantic.success,
        container: semantic.successContainer,
        icon: FLucideIcons.circleCheck,
      ),
      ToastKind.warning => _ToastPalette(
        accent: semantic.warning,
        container: semantic.warningContainer,
        icon: FLucideIcons.triangleAlert,
      ),
      ToastKind.error => _ToastPalette(
        accent: semantic.danger,
        container: semantic.dangerContainer,
        icon: FLucideIcons.circleX,
      ),
      ToastKind.info => _ToastPalette(
        accent: semantic.info,
        container: semantic.infoContainer,
        icon: FLucideIcons.info,
      ),
    };
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
