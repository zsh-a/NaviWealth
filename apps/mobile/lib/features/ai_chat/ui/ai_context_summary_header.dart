import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/composition/ai_context_summary.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// "Monthly summary" pulse rendered above the AI chat surface.
///
/// Iterates [AiContextSummary.facts] verbatim — every fact line is
/// already localised + formatted by its producing domain. The chip
/// stays domain-neutral and just paints icon + text + tone color, so
/// HealthOS / KnowledgeOS additions land alongside Finance without
/// touching this widget.
class AiContextSummaryHeader extends ConsumerWidget {
  const AiContextSummaryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builder = ref.watch(aiContextSummaryProvider);
    final l10n = AppLocalizations.of(context);
    final summary = builder(l10n);
    if (summary.isEmpty) return const SizedBox.shrink();
    final colors = context.theme.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s4),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s14, AppSpacing.s16, AppSpacing.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.aiContextSummaryThisMonth.toUpperCase(),
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < summary.facts.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s4),
              _InfoLine(fact: summary.facts[i]),
            ],
          ],
        ),
      ),
    );
  }
}

Color _toneColor(AiContextTone tone, FColors colors) => switch (tone) {
  AiContextTone.positive => colors.primary,
  AiContextTone.attention => colors.foreground,
  AiContextTone.neutral => colors.foreground,
};

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.fact});

  final AiContextFact fact;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: Icon(fact.icon, size: AppIconSizes.xs, color: _toneColor(fact.tone, colors)),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            fact.text,
            style: context.theme.typography.sm.copyWith(
              color: colors.foreground,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
