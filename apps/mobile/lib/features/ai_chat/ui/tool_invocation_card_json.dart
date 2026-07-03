part of 'tool_invocation_card.dart';

/// Monospace block with a subtle muted fill, used for raw JSON payloads.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border, width: AppStroke.hairline),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier'],
          fontSize: TypographyTokens.labelMedium.fontSize,
          height: 1.45,
          color: colors.foreground,
        ),
      ),
    );
  }
}

/// Map a wire tool name to an icon that lets the user spot at a
/// glance "this turn touched holdings" vs "this turn touched FIRE
/// buckets". The fallback is a generic gear since the catch-all
/// sparkle is already used as the assistant identity glyph
/// elsewhere - repeating it on per-tool rows muddies the signal.
IconData toolIcon(String wireName) {
  return switch (wireName) {
    // Portfolio / holdings reads
    'get_holdings' => FLucideIcons.wallet,
    'read_account_window' => FLucideIcons.landmark,
    'read_asset_window' => FLucideIcons.chartLine,
    'read_category_window' => FLucideIcons.layoutGrid,
    'list_payment_accounts' => FLucideIcons.banknote,
    // Aggregations / breakdowns
    'compute_net_worth' || 'get_net_worth_summary' => FLucideIcons.piggyBank,
    'compute_xirr' || 'get_xirr_summary' => FLucideIcons.percent,
    'get_investment_performance' => FLucideIcons.trendingUp,
    'get_asset_allocation' => FLucideIcons.chartPie,
    'get_industry_breakdown' => FLucideIcons.chartPie,
    'get_geo_breakdown' => FLucideIcons.globe,
    'get_market_cap_breakdown' => FLucideIcons.chartLine,
    'get_risk_alerts' => FLucideIcons.triangleAlert,
    'get_anomaly_flags' => FLucideIcons.zap,
    'get_cashflow_buckets' => FLucideIcons.folderTree,
    // Expense intelligence
    'get_recurring_patterns' => FLucideIcons.repeat,
    'get_subscription_changes' => FLucideIcons.playSquare,
    'get_refund_links' => FLucideIcons.undoDot,
    'get_transfer_links' => FLucideIcons.arrowLeftRight,
    // FIRE
    'get_fire_state' || 'get_fire_plan' => FLucideIcons.flag,
    'get_fire_buckets' => FLucideIcons.folderTree,
    'get_fire_review' => FLucideIcons.history,
    'get_fire_stress_tests' ||
    'simulate_fire_plan' => FLucideIcons.flaskConical,
    // Options income
    'get_options_income_opportunities' => FLucideIcons.piggyBank,
    'get_options_strategy_profile' => FLucideIcons.handshake,
    // Anything else - generic gear, never the AI sparkle (kept for
    // assistant-identity affordances elsewhere).
    _ => FLucideIcons.settings,
  };
}

/// Map a wire tool name (e.g. `get_holdings`) to a localized,
/// user-facing label (e.g. "查询持仓"). Unknown wires fall through to
/// the raw name - better than an opaque "unknown" placeholder, since
/// power users can still recognise the tool and report bugs.
String friendlyToolName(AppLocalizations l10n, String wireName) {
  return switch (wireName) {
    'get_holdings' => l10n.aiChatToolGetHoldings,
    'compute_xirr' => l10n.aiChatToolComputeXirr,
    'compute_net_worth' ||
    'get_net_worth_summary' => l10n.aiChatToolComputeNetWorth,
    'get_industry_breakdown' => l10n.aiChatToolGetIndustryBreakdown,
    'get_geo_breakdown' => l10n.aiChatToolGetGeoBreakdown,
    'get_market_cap_breakdown' => l10n.aiChatToolGetMarketCapBreakdown,
    'get_risk_alerts' => l10n.aiChatToolGetRiskAlerts,
    _ => wireName.isEmpty ? l10n.aiChatToolFallback : wireName,
  };
}

String? _summarizeInput(Object? input) {
  if (input is! Map) return null;
  final pairs = <String>[];
  for (final entry in input.entries) {
    final v = entry.value;
    if (v == null) continue;
    final str = v is String ? v : v.toString();
    if (str.isEmpty) continue;
    pairs.add('${entry.key}=$str');
    if (pairs.length >= 3) break;
  }
  return pairs.isEmpty ? null : pairs.join(' · ');
}

String _prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value?.toString() ?? 'null';
  }
}
