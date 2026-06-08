import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
import '../tokens/dimens_tokens.dart';

/// Show a forui-styled confirm dialog with frosted glass surface.
///
/// Returns `true` when the user taps the confirm action, `false` for
/// cancel, `null` if the barrier was dismissed.
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required Widget title,
  Widget? body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  IconData? icon,
}) {
  return showFDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx, style, animation) => _GlassDialog(
      accentColor: destructive
          ? SemanticColors.of(ctx).danger
          : FTheme.of(ctx).colors.primary,
      icon: icon,
      title: title,
      body: body,
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FButton(
          variant: destructive
              ? FButtonVariant.destructive
              : FButtonVariant.primary,
          onPress: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Show a forui-styled dialog that hosts arbitrary [child] content with
/// a single OK action. Returns `true` when OK is pressed, `null` on
/// barrier dismiss.
Future<bool?> showInfoDialog(
  BuildContext context, {
  required Widget title,
  Widget? body,
  required String okLabel,
  IconData? icon,
}) {
  return showFDialog<bool>(
    context: context,
    builder: (ctx, style, animation) => _GlassDialog(
      accentColor: FTheme.of(ctx).colors.primary,
      icon: icon,
      title: title,
      body: body,
      actions: [
        FButton(
          variant: FButtonVariant.primary,
          onPress: () => Navigator.of(ctx).pop(true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

/// Frosted glass dialog surface — matches the sheet aesthetic for a
/// unified glass-morphism language across the app.
class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.accentColor,
    required this.title,
    required this.actions,
    this.body,
    this.icon,
  });

  final Color accentColor;
  final Widget title;
  final Widget? body;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final surface = colors.background.withValues(
      alpha: isDark ? AppOpacity.nearOpaqueDark : AppOpacity.nearOpaque,
    );
    final borderColor = colors.foreground.withValues(
      alpha: isDark ? AppOpacity.light : AppOpacity.subtle,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: AppBlur.sheet,
          sigmaY: AppBlur.sheet,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accent bar — thin colored strip at the top for visual weight.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: AppOpacity.medium),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                ),
                child: const SizedBox(height: 3),
              ),
              // Content area.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s20,
                  AppSpacing.s16,
                  AppSpacing.s20,
                  AppSpacing.s8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: AppIconSizes.xl, color: accentColor),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    DefaultTextStyle(
                      style: context.theme.typography.lg.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      child: title,
                    ),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      DefaultTextStyle(
                        style: context.theme.typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                        child: body!,
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s20,
                  AppSpacing.s4,
                  AppSpacing.s20,
                  AppSpacing.s20,
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.s8),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
