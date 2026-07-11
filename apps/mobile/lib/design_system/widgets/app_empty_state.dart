import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_actions.dart';

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
  factory AppEmptyState.error({
    Key? key,
    required String title,
    String? message,
    Widget? action,
    String? retryLabel,
    VoidCallback? onRetry,
    IconData icon = FLucideIcons.circleX,
  }) {
    assert(
      action == null || onRetry == null,
      'Provide either action or onRetry, not both.',
    );
    assert(
      onRetry == null || retryLabel != null,
      'retryLabel is required when onRetry is provided.',
    );
    return AppEmptyState(
      key: key,
      icon: icon,
      title: title,
      message: message,
      action: onRetry == null
          ? action
          : AppActionButton(
              onPress: onRetry,
              mainAxisSize: MainAxisSize.max,
              child: Text(retryLabel!),
            ),
      tone: AppEmptyStateTone.error,
    );
  }

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
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: AppOpacity.whisper),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: iconSize + AppSpacing.s20,
                child: Center(
                  child: Icon(icon, size: iconSize, color: iconColor),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(title, style: typography.body.lg, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                message!,
                style: context.bodyCaptionStyle,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(width: double.infinity, child: action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
