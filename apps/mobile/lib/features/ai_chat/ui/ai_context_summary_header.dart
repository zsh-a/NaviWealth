import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../state/ai_context_summary_provider.dart';

/// "Monthly summary" pulse rendered above the AI chat surface.
///
/// Vertical info-stack instead of a horizontal stat grid — the
/// horizontal layout overflowed on narrow widths and read as a
/// "dashboard" instead of a calm AI status card. Each line is one
/// sentence written the way the AI would say it back to the user
/// ("Net worth +2.3% this month", "2 unusual expenses"), so the user
/// gets a verbal sense of what the assistant already knows about
/// their finances before they type a question.
///
/// Lines that have nothing to say silently drop out — an empty
/// summary widget collapses the section entirely rather than showing
/// "—" placeholders.
class AiContextSummaryHeader extends ConsumerWidget {
  const AiContextSummaryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(aiContextSummaryProvider);
    if (summary.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;

    final lines = _composeLines(l10n, summary, colors);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
            const SizedBox(height: 8),
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              _InfoLine(line: lines[i]),
            ],
          ],
        ),
      ),
    );
  }

  List<_SummaryLine> _composeLines(
    AppLocalizations l10n,
    AiContextSummary s,
    FColors colors,
  ) {
    final out = <_SummaryLine>[];
    final pct = s.monthlyChangePct;
    if (pct != null && pct.isFinite) {
      final sign = pct >= 0 ? '+' : '−';
      final abs = (pct.abs() * 100).toStringAsFixed(1);
      out.add(
        _SummaryLine(
          icon: pct >= 0
              ? Icons.trending_up_outlined
              : Icons.trending_down_outlined,
          accent: pct >= 0 ? colors.primary : colors.foreground,
          text: l10n.aiContextSummaryNetWorthLine('$sign$abs%'),
        ),
      );
    }
    if (s.unusualExpensesCount > 0) {
      out.add(
        _SummaryLine(
          icon: Icons.bolt_outlined,
          accent: colors.foreground,
          text: l10n.aiContextSummaryUnusualLine(s.unusualExpensesCount),
        ),
      );
    }
    if (s.upcomingMaturitiesCount > 0) {
      out.add(
        _SummaryLine(
          icon: Icons.event_available_outlined,
          accent: colors.foreground,
          text: l10n.aiContextSummaryUpcomingLine(
            s.upcomingMaturitiesCount,
            s.upcomingMaturitiesDays,
          ),
        ),
      );
    }
    return out;
  }
}

class _SummaryLine {
  const _SummaryLine({
    required this.icon,
    required this.accent,
    required this.text,
  });

  final IconData icon;
  final Color accent;
  final String text;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.line});

  final _SummaryLine line;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(line.icon, size: 14, color: line.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.text,
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
