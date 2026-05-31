/// Renders an `ask_user` [DecisionRequest] as an interactive choice card
/// (Claude-Code / Codex style): title + context + 2–4 option tiles with
/// pros / cons / a recommended badge. Tapping an option writes the pick
/// back as the next user turn via [onSelect]; when [interactive] is false
/// (an older, already-answered decision) the tiles render read-only.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import 'decision_request.dart';

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.request,
    required this.interactive,
    required this.onSelect,
  });

  final DecisionRequest request;

  /// Only the trailing turn's decision is actionable; past ones render
  /// read-only so a scroll-back can't re-fire a stale choice.
  final bool interactive;

  /// Called with the natural-language reply to send as the next user turn.
  final void Function(String reply) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FLucideIcons.listChecks, size: AppIconSizes.sm, color: colors.primary),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  request.title,
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (request.context.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              request.context,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          for (var i = 0; i < request.options.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            _OptionTile(
              option: request.options[i],
              onTap: interactive ? () => onSelect(_replyFor(request.options[i])) : null,
            ),
          ],
          if (request.allowCustom && interactive) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              '或在下方直接输入你的方案。',
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }

  /// Structured-but-natural reply written back to the conversation so the
  /// agent continues under the chosen constraint.
  static String _replyFor(DecisionOption o) =>
      '我选择「${o.label}」。请在此方案下继续。';
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.onTap});

  final DecisionOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: option.recommended
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    style: typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                ),
                if (option.recommended) _RecommendedBadge(),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  Icon(
                    FLucideIcons.arrowRight,
                    size: AppIconSizes.xs,
                    color: colors.mutedForeground,
                  ),
                ],
              ],
            ),
            if (option.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(
                option.description,
                style: typography.xs.copyWith(color: colors.mutedForeground),
              ),
            ],
            for (final pro in option.pros) _Tradeoff(text: pro, positive: true),
            for (final con in option.cons) _Tradeoff(text: con, positive: false),
          ],
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '推荐',
        style: typography.xs.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Tradeoff extends StatelessWidget {
  const _Tradeoff({required this.text, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? FLucideIcons.check : FLucideIcons.minus,
            size: 12,
            color: positive ? colors.primary : colors.mutedForeground,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
