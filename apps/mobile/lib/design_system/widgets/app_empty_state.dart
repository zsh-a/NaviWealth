import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Tone of an [AppEmptyState] — drives the icon tint.
///
/// `neutral` is for "nothing here yet" (icon picks up the primary
/// accent so the CTA reads as inviting). `error` is for failed
/// loads (icon goes destructive so the page reads as recoverable
/// failure, not blank state).
enum AppEmptyStateTone { neutral, error }

/// Unified empty / error / placeholder state.
///
/// Replaces the per-feature `_EmptyState` / `_ErrorBody` widgets that
/// drifted in icon size, gap rhythm, and button variant. Layout matches
/// the FIRE / cashflow patterns that already shipped — icon + title +
/// optional message + optional CTA, centred with consistent spacing.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = AppEmptyStateTone.neutral,
    this.iconSize = AppIconSizes.xxl,
  });

  /// Convenience constructor for "couldn't load" failures with an
  /// optional retry callback. Uses [AppEmptyStateTone.error] and the
  /// standard error icon so error states across the app look the same.
  const AppEmptyState.error({
    Key? key,
    required String title,
    String? message,
    Widget? action,
    IconData icon = Icons.error_outline,
  }) : this(
         key: key,
         icon: icon,
         title: title,
         message: message,
         action: action,
         tone: AppEmptyStateTone.error,
       );

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppEmptyStateTone tone;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final iconColor = switch (tone) {
      AppEmptyStateTone.neutral => colors.primary,
      AppEmptyStateTone.error => colors.destructive,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: iconColor),
            const SizedBox(height: AppSpacing.s16),
            Text(title, style: typography.lg, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                message!,
                style: typography.sm.copyWith(color: colors.mutedForeground),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
