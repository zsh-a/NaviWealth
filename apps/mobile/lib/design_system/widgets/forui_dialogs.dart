import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

/// Shows arbitrary app-styled dialog content in a centered, width-constrained
/// frame. Feature code should use this seam instead of calling [showFDialog]
/// directly so desktop dialog geometry stays consistent.
Future<T?> showAppContentDialog<T>({
  required BuildContext context,
  required Widget child,
  double maxWidth = 560,
  bool barrierDismissible = true,
}) {
  return showFDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context, style, animation) => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
  );
}

/// Show a compact, calm confirmation dialog.
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
    builder: (ctx, style, animation) => _DialogFrame(
      child: _AppDialog(
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
            child: _DialogButtonLabel(cancelLabel),
          ),
          FButton(
            variant: destructive
                ? FButtonVariant.destructive
                : FButtonVariant.primary,
            onPress: () => Navigator.of(ctx).pop(true),
            child: _DialogButtonLabel(confirmLabel),
          ),
        ],
      ),
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
    builder: (ctx, style, animation) => _DialogFrame(
      child: _AppDialog(
        accentColor: FTheme.of(ctx).colors.primary,
        icon: icon,
        title: title,
        body: body,
        actions: [
          FButton(
            variant: FButtonVariant.primary,
            onPress: () => Navigator.of(ctx).pop(true),
            child: _DialogButtonLabel(okLabel),
          ),
        ],
      ),
    ),
  );
}

/// Show a non-dismissable progress dialog and return a callback that closes it.
Future<Future<void> Function()> showProgressDialog({
  required BuildContext context,
  required String message,
}) async {
  final completer = Completer<VoidCallback>();
  unawaited(
    showFDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx, style, animation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!completer.isCompleted) {
            completer.complete(() => Navigator.of(ctx).pop());
          }
        });
        return _DialogFrame(
          child: _AppDialog(
            accentColor: FTheme.of(ctx).colors.primary,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FCircularProgress(),
                const SizedBox(width: AppSpacing.s16),
                Flexible(child: Text(message)),
              ],
            ),
            actions: const [],
          ),
        );
      },
    ),
  );
  final dismiss = await completer.future;
  return () async => dismiss();
}

class _DialogButtonLabel extends StatelessWidget {
  const _DialogButtonLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          460.0,
          math.max(0.0, constraints.maxWidth - AppSpacing.s32),
        );
        return Center(
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}

class _AppDialog extends StatelessWidget {
  const _AppDialog({
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
    final surface = colors.background;
    final borderColor = colors.foreground.withValues(
      alpha: colors.brightness == Brightness.dark
          ? AppOpacity.light
          : AppOpacity.subtle,
    );

    return DecoratedBox(
      key: const ValueKey<String>('app-dialog-surface'),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor, width: AppStroke.hairline),
        boxShadow: [
          BoxShadow(
            color: colors.foreground.withValues(alpha: AppOpacity.whisper),
            blurRadius: AppSpacing.s32,
            offset: const Offset(0, AppSpacing.s12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s20,
              AppSpacing.s20,
              AppSpacing.s8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: AppOpacity.whisper),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: AppSpacing.s40,
                      child: Icon(
                        icon,
                        size: AppIconSizes.h18,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                ],
                DefaultTextStyle(style: context.titleLabelStyle, child: title),
                if (body != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  DefaultTextStyle(
                    style: context.bodyCaptionStyle.copyWith(height: 1.45),
                    child: body!,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s20,
                AppSpacing.s8,
                AppSpacing.s20,
                AppSpacing.s20,
              ),
              child: _DialogActions(actions: actions),
            ),
        ],
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.length == 1) {
      return SizedBox(width: double.infinity, child: actions.single);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s8),
                actions[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s12),
              Expanded(child: actions[i]),
            ],
          ],
        );
      },
    );
  }
}
