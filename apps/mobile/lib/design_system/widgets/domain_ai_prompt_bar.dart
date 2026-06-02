import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'soft_card.dart';

class DomainAiPromptAction {
  const DomainAiPromptAction({
    required this.label,
    required this.icon,
    required this.onPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPress;
}

/// Compact domain-level AI entry used inside task pages.
class DomainAiPromptBar extends StatelessWidget {
  const DomainAiPromptBar({
    super.key,
    required this.hint,
    required this.onPress,
    this.actions = const <DomainAiPromptAction>[],
  });

  final String hint;
  final VoidCallback onPress;
  final List<DomainAiPromptAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          onPress: onPress,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(
                FLucideIcons.sparkles,
                size: AppIconSizes.sm,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  hint,
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                FLucideIcons.arrowRight,
                size: AppIconSizes.sm,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final action in actions)
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: action.onPress,
                  prefix: Icon(action.icon, size: AppIconSizes.xs),
                  child: Text(action.label),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
