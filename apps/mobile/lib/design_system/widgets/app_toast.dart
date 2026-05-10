import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../theme/semantic_colors.dart';
import '../tokens/glass_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/spacing_tokens.dart';

/// Toast severity levels.
enum ToastKind {
  success,
  warning,
  error,
  info,
}

/// Top-anchored glass toast that replaces Material's bottom SnackBar.
///
/// Usage:
/// ```dart
/// AppMessenger.show(context, ToastKind.success, 'Saved');
/// ```
///
/// Call [AppMessenger.init] once in the [MaterialApp.builder] to install
/// the overlay host. Then use [AppMessenger.show] from anywhere.
class AppMessenger {
  AppMessenger._();

  static final AppMessenger _instance = AppMessenger._();
  static AppMessenger get instance => _instance;

  OverlayEntry? _currentEntry;
  Timer? _dismissTimer;

  /// Cached overlay reference. On first [show] call with a valid context
  /// the overlay is captured; subsequent calls reuse it even when the
  /// originating context has been disposed (e.g. after Navigator.pop).
  OverlayState? _cachedOverlay;

  /// Install the toast overlay host. Call in [MaterialApp.builder].
  static Widget init({required Widget child}) {
    return _ToastHost(child: child);
  }

  /// Caches the overlay found via [context] so that [show] can insert
  /// toasts even after the context is unmounted (e.g. after a pop).
  static void cacheOverlay(BuildContext context) {
    try {
      _instance._cachedOverlay ??= Overlay.maybeOf(context);
    } catch (_) {
      // Context may already be unmounted.
    }
  }

  /// Show a toast. Automatically dismisses after [duration].
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
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    // Try the caller's context first; fall back to the cached overlay
    // (which survives after the originating widget is popped).
    OverlayState? overlay;
    try {
      overlay = Overlay.maybeOf(context);
    } catch (_) {
      // Context may be unmounted after a Navigator.pop.
    }
    overlay ??= _cachedOverlay;
    if (overlay == null) return;
    _cachedOverlay = overlay;

    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        kind: kind,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          _dismissTimer?.cancel();
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      entry.remove();
      if (_currentEntry == entry) _currentEntry = null;
    });
  }
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.child});

  final Widget child;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  @override
  void dispose() {
    AppMessenger._instance._cachedOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  final ToastKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.medium,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext context) {
    final semantic = SemanticColors.of(context);
    return switch (widget.kind) {
      ToastKind.success => semantic.success,
      ToastKind.warning => semantic.warning,
      ToastKind.error => semantic.danger,
      ToastKind.info => semantic.info,
    };
  }

  IconData _icon() {
    return switch (widget.kind) {
      ToastKind.success => Icons.check_circle_outline_rounded,
      ToastKind.warning => Icons.warning_amber_rounded,
      ToastKind.error => Icons.error_outline_rounded,
      ToastKind.info => Icons.info_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + Spacing.s16;
    final tokens = GlassTokens.of(context);
    final accent = _accentColor(context);
    final theme = Theme.of(context);

    return Positioned(
      top: topPadding,
      left: Spacing.s16,
      right: Spacing.s16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Semantics(
            liveRegion: true,
            label: widget.message,
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.hairlineColor, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: lgw.GlassContainer(
                  shape: const lgw.LiquidRoundedRectangle(borderRadius: 12),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: accent, width: 3),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.s12,
                      vertical: Spacing.s12,
                    ),
                    child: Row(
                      children: [
                        Icon(_icon(), color: accent, size: 20),
                        const SizedBox(width: Spacing.s8),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (widget.actionLabel != null &&
                            widget.onAction != null)
                          GestureDetector(
                            onTap: () {
                              widget.onAction?.call();
                              widget.onDismiss();
                            },
                            child: Text(
                              widget.actionLabel!,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        const SizedBox(width: Spacing.s4),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
