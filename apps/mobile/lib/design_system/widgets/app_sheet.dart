import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

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
}) {
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: maxHeightFactor,
    builder: (sheetContext) => AppSheet(
      title: title,
      subtitle: subtitle,
      actions: actions,
      footer: footer,
      scrollable: scrollable,
      child: Builder(builder: builder),
    ),
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
}) {
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: maxHeightFactor,
    builder: builder,
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

  Widget _header(BuildContext context) {
    final colors = context.theme.colors;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s4,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
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
        alpha: colors.brightness == Brightness.dark ? 0.12 : 0.10,
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s4,
                  AppSpacing.s16,
                  AppSpacing.s12,
                ),
                child: child,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: hairline)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s12,
                  AppSpacing.s16,
                  AppSpacing.s12,
                ),
                child: footer,
              ),
            ),
          ],
        ),
      );
    }

    // ── Legacy branch: unchanged behaviour for existing showAppSheet
    // call sites (mainAxisSize.min + AnimatedSize, no pinned footer).
    final body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s4,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: child,
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s4,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: child,
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dragHandle(colors),
        _header(context),
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.standardDecelerate,
          alignment: Alignment.topCenter,
          child: body,
        ),
      ],
    );

    return AppSheetSurface(child: content);
  }

  // Drag handle — small, muted, centered. One spec for the whole app.
  static Widget _dragHandle(FColors colors) {
    return Center(
      child: Container(
        width: 36,
        height: AppSpacing.s4,
        margin: const EdgeInsets.only(top: 10, bottom: AppSpacing.s6),
        decoration: BoxDecoration(
          color: colors.mutedForeground.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
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
    this.cancelLabel,
    this.onCancel,
    this.busy = false,
    this.destructive = false,
  });

  final String submitLabel;
  final VoidCallback onSubmit;

  /// Defaults to "Cancel" when null is passed by the caller's l10n.
  final String? cancelLabel;

  /// Defaults to `Navigator.maybePop()` when null.
  final VoidCallback? onCancel;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            onPress: busy
                ? null
                : (onCancel ?? () => Navigator.of(context).maybePop()),
            child: Text(cancelLabel ?? 'Cancel'),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: FButton(
            variant: destructive
                ? FButtonVariant.destructive
                : FButtonVariant.primary,
            onPress: busy ? null : onSubmit,
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.primaryForeground,
                      ),
                    ),
                  )
                : Text(submitLabel),
          ),
        ),
      ],
    );
  }
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
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final surface = colors.background.withValues(alpha: isDark ? 0.98 : 0.97);
    final hairline = colors.foreground.withValues(alpha: isDark ? 0.12 : 0.10);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            border:
                border ?? Border(top: BorderSide(color: hairline, width: 1)),
          ),
          child: SafeArea(top: safeTop, bottom: safeBottom, child: child),
        ),
      ),
    );
  }
}
