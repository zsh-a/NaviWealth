import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/motion_utils.dart';

enum AppQuietButtonTone { neutral, danger }

/// Low-emphasis action button for secondary commands inside cards and banners.
///
/// Use this when an action should remain discoverable without adding the
/// visual weight of an outline or primary button. Primary task actions should
/// still use [FButton] or [AppBusyButton].
class AppQuietButton extends StatelessWidget {
  const AppQuietButton({
    super.key,
    required this.label,
    required this.onPress,
    this.prefix,
    this.busyPrefix,
    this.busy = false,
    this.busyLabel,
    this.expanded = false,
    this.tone = AppQuietButtonTone.neutral,
  });

  final String label;
  final VoidCallback? onPress;
  final Widget? prefix;
  final Widget? busyPrefix;
  final bool busy;
  final String? busyLabel;
  final bool expanded;
  final AppQuietButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    final enabled = onPress != null && !busy;
    final activeForeground = switch (tone) {
      AppQuietButtonTone.neutral => colors.foreground,
      AppQuietButtonTone.danger => semantic.danger,
    };
    final activeContainer = switch (tone) {
      AppQuietButtonTone.neutral => colors.muted.withValues(
        alpha: AppOpacity.disabled,
      ),
      AppQuietButtonTone.danger => semantic.dangerContainer,
    };
    final foreground = enabled
        ? activeForeground
        : colors.mutedForeground.withValues(alpha: AppOpacity.disabled);
    final effectiveLabel = busy ? (busyLabel ?? label) : label;
    final effectivePrefix = busy
        ? busyPrefix ??
              const SizedBox(
                width: AppIconSizes.xs,
                height: AppIconSizes.xs,
                child: FCircularProgress(size: FCircularProgressSizeVariant.xs),
              )
        : prefix;

    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (effectivePrefix != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: foreground, size: AppIconSizes.xs),
            child: effectivePrefix,
          ),
          const SizedBox(width: AppSpacing.s6),
        ],
        Flexible(
          fit: expanded ? FlexFit.tight : FlexFit.loose,
          child: Text(
            effectiveLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: FTappable(
        onPress: enabled ? onPress : null,
        child: AnimatedContainer(
          duration: motionDuration(context, Motion.fast),
          curve: Motion.standard,
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? activeContainer
                : colors.muted.withValues(alpha: AppOpacity.subtle),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: foreground.withValues(alpha: AppOpacity.light),
            ),
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: context.theme.typography.sm.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
