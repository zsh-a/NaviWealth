import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_overlay_surface.dart';
import 'app_sheet.dart';
import 'app_status_banner.dart';

/// Shows arbitrary app-styled dialog content in a centered, width-constrained
/// frame. Feature code should use this seam instead of calling [showFDialog]
/// directly so desktop dialog geometry stays consistent.
Future<T?> showAppContentDialog<T>({
  required BuildContext context,
  required Widget child,
  double maxWidth = Breakpoints.dialogWide,
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
/// Returns `true` when the user taps the confirm action, `false` for cancel,
/// and `null` when they tap outside. Barrier dismissal is intentionally
/// equivalent to cancel: it keeps destructive actions safe without trapping
/// users inside a routine decision.
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
    barrierDismissible: true,
    builder: (ctx, style, animation) => _DialogFrame(
      child: _AppDialog(
        accentColor: destructive
            ? ctx.appTheme.status.danger.fg
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

/// Shows a single-field prompt using the same keyboard-safe sheet and Forui
/// controls as the rest of the app. Use this instead of a Material
/// [AlertDialog] for names, amounts, reasons, and other short values.
Future<String?> showAppTextPromptSheet({
  required BuildContext context,
  required String title,
  required String fieldLabel,
  required String submitLabel,
  required String cancelLabel,
  String initialValue = '',
  String? hint,
  TextInputType keyboardType = TextInputType.text,
  String? Function(String value)? validator,
}) {
  return showAppFormSheet<String>(
    context: context,
    builder: (_) => _TextPromptSheet(
      title: title,
      fieldLabel: fieldLabel,
      submitLabel: submitLabel,
      cancelLabel: cancelLabel,
      initialValue: initialValue,
      hint: hint,
      keyboardType: keyboardType,
      validator: validator,
    ),
  );
}

class _TextPromptSheet extends StatefulWidget {
  const _TextPromptSheet({
    required this.title,
    required this.fieldLabel,
    required this.submitLabel,
    required this.cancelLabel,
    required this.initialValue,
    required this.hint,
    required this.keyboardType,
    required this.validator,
  });

  final String title;
  final String fieldLabel;
  final String submitLabel;
  final String cancelLabel;
  final String initialValue;
  final String? hint;
  final TextInputType keyboardType;
  final String? Function(String value)? validator;

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: widget.title,
      footer: AppSheetFooter(
        submitLabel: widget.submitLabel,
        cancelLabel: widget.cancelLabel,
        onSubmit: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            autofocus: true,
            control: FTextFieldControl.managed(controller: _controller),
            keyboardType: widget.keyboardType,
            label: Text(widget.fieldLabel),
            hint: widget.hint,
            onSubmit: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }
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
          Breakpoints.dialogMax,
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
    return AppOverlaySurface(
      key: const ValueKey<String>('app-dialog-surface'),
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
