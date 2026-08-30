import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_actions.dart';
import 'app_interaction.dart';

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
    this.iconSize = AppIconSizes.xl,
    this.compact = false,
    this.inline = false,
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
    bool compact = false,
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
      compact: compact,
    );
  }

  /// Compact inline variant for section / card bodies. Keeps the same
  /// icon + title + optional message language, but as a left-aligned row
  /// so summary cards can host an empty / error hint without handing over
  /// the full viewport. [onRetry] builds the standard ghost retry action.
  factory AppEmptyState.inline({
    Key? key,
    required IconData icon,
    required String title,
    String? message,
    Widget? action,
    AppEmptyStateTone tone = AppEmptyStateTone.neutral,
    String? retryLabel,
    VoidCallback? onRetry,
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
          : FButton(
              variant: FButtonVariant.ghost,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
              onPress: AppInteraction.wrap(onRetry),
              child: Text(retryLabel!),
            ),
      tone: tone,
      inline: true,
    );
  }

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppEmptyStateTone tone;
  final double iconSize;
  final bool compact;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final iconColor = switch (tone) {
      AppEmptyStateTone.neutral => colors.primary,
      AppEmptyStateTone.error => colors.destructive,
    };
    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Icon(icon, size: AppIconSizes.sm, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.labelStyle),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(message!, style: context.captionStyle),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.s8),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.s16 : AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: AppOpacity.whisper),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension:
                    iconSize + (compact ? AppSpacing.s12 : AppSpacing.s16),
                child: Center(
                  child: Icon(icon, size: iconSize, color: iconColor),
                ),
              ),
            ),
            SizedBox(height: compact ? AppSpacing.s10 : AppSpacing.s14),
            Text(title, style: typography.body.lg, textAlign: TextAlign.center),
            if (message != null) ...[
              SizedBox(height: compact ? AppSpacing.s4 : AppSpacing.s8),
              Text(
                message!,
                style: context.bodyCaptionStyle,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? AppSpacing.s10 : AppSpacing.s16),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppControlWidths.emptyStateAction,
                ),
                child: SizedBox(width: double.infinity, child: action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
