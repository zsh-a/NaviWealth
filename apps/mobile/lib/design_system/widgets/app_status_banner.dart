import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';
import 'pressable_scale.dart';

enum AppStatusKind { neutral, info, success, warning, error }

/// Canonical inline status banner for page notices and compact sync states.
class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({
    super.key,
    required this.message,
    this.kind = AppStatusKind.info,
    this.details,
    this.icon,
    this.action,
    this.compact = false,
    this.onPress,
    this.semanticLabel,
  });

  final String message;
  final AppStatusKind kind;
  final String? details;
  final IconData? icon;
  final Widget? action;
  final bool compact;
  final VoidCallback? onPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final palette = _StatusPalette.resolve(context, kind);
    final hasDetails = details != null && details!.isNotEmpty;
    final banner = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: palette.foreground.withValues(alpha: AppOpacity.light),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.s10 : AppSpacing.s12),
        child: Row(
          crossAxisAlignment: hasDetails || action != null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Icon(
              icon ?? palette.icon,
              color: palette.foreground,
              size: compact ? AppIconSizes.h18 : AppIconSizes.md,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: compact
                        ? context.captionStyle
                        : context.theme.typography.body.sm.copyWith(
                            color: colors.foreground,
                          ),
                    maxLines: compact ? 2 : null,
                    overflow: compact ? TextOverflow.ellipsis : null,
                  ),
                  if (hasDetails) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(details!, style: context.captionStyle),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.s8),
              action!,
            ],
          ],
        ),
      ),
    );
    if (onPress == null) return banner;
    return Semantics(
      button: true,
      label: semanticLabel ?? message,
      child: PressableScale(
        onTap: onPress,
        intent: AppInteractionIntent.reveal,
        child: banner,
      ),
    );
  }
}

class _StatusPalette {
  const _StatusPalette({
    required this.foreground,
    required this.container,
    required this.icon,
  });

  final Color foreground;
  final Color container;
  final IconData icon;

  static _StatusPalette resolve(BuildContext context, AppStatusKind kind) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    return switch (kind) {
      AppStatusKind.neutral => _StatusPalette(
        foreground: colors.mutedForeground,
        container: colors.muted,
        icon: FLucideIcons.info,
      ),
      // Container fills take the on-container foreground; the bare status
      // color fails WCAG AA on its own tint. See theme_contrast_test.dart.
      AppStatusKind.info => _StatusPalette(
        foreground: status.info.onContainer,
        container: status.info.container,
        icon: FLucideIcons.info,
      ),
      AppStatusKind.success => _StatusPalette(
        foreground: status.success.onContainer,
        container: status.success.container,
        icon: FLucideIcons.circleCheck,
      ),
      AppStatusKind.warning => _StatusPalette(
        foreground: status.warning.onContainer,
        container: status.warning.container,
        icon: FLucideIcons.triangleAlert,
      ),
      AppStatusKind.error => _StatusPalette(
        foreground: status.danger.onContainer,
        container: status.danger.container,
        icon: FLucideIcons.circleAlert,
      ),
    };
  }
}
