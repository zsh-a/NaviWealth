import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/semantic_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

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
  });

  final String message;
  final AppStatusKind kind;
  final String? details;
  final IconData? icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final palette = _StatusPalette.resolve(context, kind);
    final hasDetails = details != null && details!.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
    final semantic = SemanticColors.of(context);
    return switch (kind) {
      AppStatusKind.neutral => _StatusPalette(
        foreground: colors.mutedForeground,
        container: colors.muted,
        icon: FLucideIcons.info,
      ),
      AppStatusKind.info => _StatusPalette(
        foreground: semantic.info,
        container: semantic.infoContainer,
        icon: FLucideIcons.info,
      ),
      AppStatusKind.success => _StatusPalette(
        foreground: semantic.success,
        container: semantic.successContainer,
        icon: FLucideIcons.circleCheck,
      ),
      AppStatusKind.warning => _StatusPalette(
        foreground: semantic.warning,
        container: semantic.warningContainer,
        icon: FLucideIcons.triangleAlert,
      ),
      AppStatusKind.error => _StatusPalette(
        foreground: semantic.danger,
        container: semantic.dangerContainer,
        icon: FLucideIcons.circleAlert,
      ),
    };
  }
}
