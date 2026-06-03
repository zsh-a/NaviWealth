import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'form_dirty_controller.dart';

/// Unified bottom-sheet shell — every modal sheet in the app should
/// reach the screen through [showAppSheet] / [showAppFormSheet] so the
/// drag handle, title row, surface tint, padding, keyboard avoidance and
/// dismiss affordance look identical.
///
/// Background is rendered as iOS-style frosted glass:
///   - `BackdropFilter(blur 18)` over whatever's underneath
///   - near-opaque base surface so the page below does not compete
///   - rounded top corners (20dp) so the sheet reads as a card edge
///     against the page below
///
/// Drop-in replacement for `showFSheet`; the [builder] receives a
/// `BuildContext` for the sheet body. Pass [title] / [subtitle] /
/// [actions] for the header row, [footer] for a pinned action bar that
/// stays above the keyboard (see [AppSheetFooter]), [scrollable] when the
/// body is a list (default true so long sheets won't blow out on small
/// phones).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  List<Widget> actions = const [],
  Widget? footer,
  bool scrollable = true,
  double? maxHeightFactor,
  FormDirtyController? dirtyGuard,
  Future<bool> Function()? confirmDismiss,
}) {
  final guarded = dirtyGuard != null;
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: maxHeightFactor,
    // When the sheet is guarding unsaved input the barrier-tap and
    // swipe-down vectors must be closed: forui dismisses both with a
    // direct `Navigator.pop`, which bypasses [PopScope]. The footer
    // Cancel and system back (both guarded) remain the only way out.
    barrierDismissible: !guarded,
    draggable: !guarded,
    builder: (sheetContext) {
      final sheet = AppSheet(
        title: title,
        subtitle: subtitle,
        actions: actions,
        footer: footer,
        scrollable: scrollable,
        child: Builder(builder: builder),
      );
      if (!guarded) return sheet;
      return _GuardedSheet(
        controller: dirtyGuard,
        confirmDismiss: confirmDismiss,
        child: sheet,
      );
    },
  );
}

/// Preset for form sheets ("add asset", "edit goal", …).
///
/// Standardises the present call (bottom side, safe-area handled by the
/// shared surface, a bounded max height so the body can scroll and the
/// [AppSheetFooter] can pin above the keyboard). The [builder] should
/// return an [AppSheet] with a [AppSheet.footer] — the form keeps owning
/// its controllers/validation, it just stops re-implementing chrome.
Future<T?> showAppFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFactor = 0.94,
  FormDirtyController? dirtyGuard,
  Future<bool> Function()? confirmDismiss,
}) {
  final guarded = dirtyGuard != null;
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: maxHeightFactor,
    // See [showAppSheet]: barrier-tap / swipe-down bypass PopScope, so
    // they are disabled while the form holds unsaved input.
    barrierDismissible: !guarded,
    draggable: !guarded,
    builder: guarded
        ? (sheetContext) => AppSheetSurface(
            child: _GuardedSheet(
              controller: dirtyGuard,
              confirmDismiss: confirmDismiss,
              child: Builder(builder: builder),
            ),
          )
        : (sheetContext) => AppSheetSurface(child: Builder(builder: builder)),
  );
}

/// Internal shell — wraps the body with the unified chrome. Public
/// only so existing call sites that already wired their own
/// `showFSheet` can migrate without changing their open mechanism.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.footer,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  /// Optional pinned action bar. When set the body scrolls within the
  /// remaining height and the footer stays docked above the keyboard.
  /// Prefer [AppSheetFooter] for the canonical Cancel/primary layout.
  final Widget? footer;
  final bool scrollable;

  // ── Canonical padding constants ──────────────────────────────────────
  // Three padding sets share the s16 horizontal column but differ on the
  // vertical axis because each band has a different neighbour:
  //   - header sits below the drag handle and above the body
  //   - body sits below the header (which already adds s8 bottom)
  //   - footer sits below the hairline and above the safe area
  // Pulling the magic numbers up here keeps the relationship explicit so
  // chrome-wide restyles are a one-edit job.

  /// Header padding — asymmetric: extra left (s20) gives the title breathing
  /// room; tighter right (s12) because action buttons / close icons sit there
  /// and don't need the full column inset.
  static const EdgeInsets kHeaderPadding = EdgeInsets.fromLTRB(
    AppSpacing.s20,
    AppSpacing.s4,
    AppSpacing.s12,
    AppSpacing.s8,
  );

  /// Body padding when a [footer] is present — bottom is tight (s12) because
  /// the footer's own s12 top padding adds the rest of the breathing room.
  static const EdgeInsets kBodyWithFooterPadding = EdgeInsets.fromLTRB(
    AppSpacing.s16,
    AppSpacing.s4,
    AppSpacing.s16,
    AppSpacing.s12,
  );

  /// Body padding when no footer is present — bottom expands to s16 so the
  /// body has full breathing room above the safe area.
  static const EdgeInsets kBodyPadding = EdgeInsets.fromLTRB(
    AppSpacing.s16,
    AppSpacing.s4,
    AppSpacing.s16,
    AppSpacing.s16,
  );

  /// Footer padding — symmetric vertical so the buttons sit clear of both
  /// the hairline above and the safe area below.
  static const EdgeInsets kFooterPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.s16,
    vertical: AppSpacing.s12,
  );

  Widget _header(BuildContext context) {
    final colors = context.theme.colors;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Padding(
      padding: kHeaderPadding,
      child: Row(
        crossAxisAlignment: hasSubtitle
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.theme.typography.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle!,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    // ── Footer branch: scrollable body + pinned, keyboard-aware footer.
    //
    // Keyboard avoidance is owned entirely by forui's modal sheet
    // (`showFSheet(resizeToAvoidBottomInset: true)`), which translates
    // the whole min-sized sheet — footer included — up above the
    // keyboard. We must NOT also pad by `viewInsets.bottom` here: that
    // double-counts the keyboard, inflating the sheet so it's jammed to
    // the top with a keyboard-sized empty band above the keyboard.
    if (footer != null) {
      final hairline = colors.foreground.withValues(
        alpha: colors.brightness == Brightness.dark
            ? AppOpacity.light
            : AppOpacity.subtle,
      );
      return AppSheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dragHandle(colors),
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: kBodyWithFooterPadding,
                child: child,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: hairline)),
              ),
              child: Padding(padding: kFooterPadding, child: footer),
            ),
          ],
        ),
      );
    }

    // ── Legacy branch: unchanged behaviour for existing showAppSheet
    // call sites (mainAxisSize.min + AnimatedSize, no pinned footer).
    final body = scrollable
        ? SingleChildScrollView(padding: kBodyPadding, child: child)
        : Padding(padding: kBodyPadding, child: child);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dragHandle(colors),
        _header(context),
        Flexible(
          child: AnimatedSize(
            duration: Motion.fast,
            curve: Motion.standardDecelerate,
            alignment: Alignment.topCenter,
            child: body,
          ),
        ),
      ],
    );

    return AppSheetSurface(child: content);
  }

  // Drag handle — small, muted, centered. One spec for the whole app.
  // Excluded from semantics — purely decorative.
  static Widget _dragHandle(FColors colors) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width:
              AppSpacing.s32 +
              AppSpacing.s4, // 36 — wider than radius for pill shape
          height: AppSpacing.s4,
          margin: const EdgeInsets.only(
            top:
                AppSpacing.s8 +
                AppSpacing.s2, // 10 — sits below the sheet's top corner
            bottom: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: colors.mutedForeground.withValues(alpha: AppOpacity.muted),
            borderRadius: BorderRadius.circular(AppSpacing.s2),
          ),
        ),
      ),
    );
  }
}

/// Canonical footer for [AppSheet] form/confirm sheets.
///
/// Layout is fixed so every sheet reads the same: a secondary outline
/// action on the left, the primary (or destructive) action on the
/// right, both expanded with a 12dp gutter. While [busy] the primary
/// action shows a spinner and both buttons are disabled.
class AppSheetFooter extends StatelessWidget {
  const AppSheetFooter({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.submitKey,
    required this.cancelLabel,
    this.onCancel,
    this.cancelKey,
    this.busy = false,
    this.destructive = false,
  });

  final String submitLabel;
  final VoidCallback onSubmit;
  final Key? submitKey;

  /// Localized cancel label — callers must pass from `AppLocalizations`.
  final String cancelLabel;

  /// Defaults to `Navigator.maybePop()` when null.
  final VoidCallback? onCancel;
  final Key? cancelKey;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FButton(
            key: cancelKey,
            variant: FButtonVariant.outline,
            onPress: busy
                ? null
                : (onCancel ?? () => Navigator.of(context).maybePop()),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: FButton(
            key: submitKey,
            variant: destructive
                ? FButtonVariant.destructive
                : FButtonVariant.primary,
            onPress: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: AppIconSizes.h18,
                    height: AppIconSizes.h18,
                    child: FCircularProgress(
                      size: FCircularProgressSizeVariant.sm,
                    ),
                  )
                : Text(submitLabel),
          ),
        ),
      ],
    );
  }
}

/// Wraps a guarded sheet body in a [PopScope] so system / predictive
/// back and the footer Cancel funnel through [confirmDismiss]. Barrier
/// tap and swipe-down are disabled by the caller (they bypass PopScope),
/// so this plus the footer Cancel are the only exits. While
/// [FormDirtyController.busy] every dismissal is swallowed so a
/// half-written record can't be abandoned mid-submit.
class _GuardedSheet extends StatelessWidget {
  const _GuardedSheet({
    required this.controller,
    required this.confirmDismiss,
    required this.child,
  });

  final FormDirtyController controller;
  final Future<bool> Function()? confirmDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        return PopScope(
          canPop: !controller.isDirty && !controller.busy,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || controller.busy) return;
            final ok = confirmDismiss == null ? true : await confirmDismiss!();
            if (ok && context.mounted) Navigator.of(context).pop();
          },
          child: child!,
        );
      },
    );
  }
}

class _AppSheetSurfaceScope extends InheritedWidget {
  const _AppSheetSurfaceScope({required super.child});

  static bool hasSurface(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppSheetSurfaceScope>() != null;

  @override
  bool updateShouldNotify(_AppSheetSurfaceScope oldWidget) => false;
}

/// Shared sheet surface for custom sheet bodies that cannot use [AppSheet].
class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(
      top: Radius.circular(AppRadius.xl),
    ),
    this.border,
    this.safeTop = false,
    this.safeBottom = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Border? border;
  final bool safeTop;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) {
    if (_AppSheetSurfaceScope.hasSurface(context)) return child;

    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final surface = colors.background.withValues(
      alpha: isDark ? AppOpacity.nearOpaqueDark : AppOpacity.nearOpaque,
    );
    final hairline = colors.foreground.withValues(
      alpha: isDark ? AppOpacity.light : AppOpacity.subtle,
    );

    return _AppSheetSurfaceScope(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: AppBlur.sheet,
            sigmaY: AppBlur.sheet,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              border:
                  border ?? Border(top: BorderSide(color: hairline, width: 1)),
            ),
            child: SafeArea(top: safeTop, bottom: safeBottom, child: child),
          ),
        ),
      ),
    );
  }
}
