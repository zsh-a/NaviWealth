import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_actions.dart';

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
    final status = context.appTheme.status;
    final enabled = onPress != null && !busy;
    final activeForeground = switch (tone) {
      AppQuietButtonTone.neutral => colors.foreground,
      AppQuietButtonTone.danger => status.danger.fg,
    };
    final foreground = enabled || busy
        ? activeForeground
        : colors.mutedForeground.withValues(alpha: AppOpacity.disabled);
    final style = context.theme.buttonStyles.ghost.resolve({
      FButtonSizeVariant.md,
      context.platformVariant,
    });
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

    return AppActionTappable(
      semanticsLabel: effectiveLabel,
      onPress: enabled ? onPress : null,
      style: style.tappableStyle,
      focusedOutlineStyle: style.focusedOutlineStyle,
      builder: (context, variants, child) => AnimatedContainer(
        duration: AppMotionPolicy.duration(
          context,
          Motion.fast,
          role: AppMotionRole.decorative,
        ),
        curve: Motion.standard,
        constraints: style.contentStyle.constraints,
        padding: style.contentStyle.padding,
        decoration: style.decoration.resolve(busy ? {} : variants),
        child: child,
      ),
      child: DefaultTextStyle.merge(
        style: context.mediumLabelStyle.copyWith(color: foreground),
        child: content,
      ),
    );
  }
}
