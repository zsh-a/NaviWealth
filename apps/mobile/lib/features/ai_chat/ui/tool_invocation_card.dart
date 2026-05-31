import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/evidence_anchor.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/chat_models.dart';
import 'tool_invocation_renderers.dart';

/// Collapsible card surfacing one tool invocation. Header shows the
/// human-friendly tool name + a one-line summary; the body (when
/// expanded) renders pretty-printed JSON for the input and output
/// payloads so the user can see exactly what the model queried.
///
/// When the tool's output references known entities (asset_id,
/// journal_entry_id, account_id), we surface a "跳到资产" / ledger
/// chip so the user can jump straight to the relevant detail page.
class ToolInvocationCard extends StatefulWidget {
  const ToolInvocationCard({super.key, required this.invocation});

  final ToolInvocation invocation;

  @override
  State<ToolInvocationCard> createState() => _ToolInvocationCardState();
}

class _ToolInvocationCardState extends State<ToolInvocationCard> {
  bool _expanded = false;
  bool _showRawJson = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invocation = widget.invocation;
    final pending = invocation.output == null;
    final friendlyName = friendlyToolName(l10n, invocation.name);
    final summary = _summarizeInput(invocation.input);
    final jumps = _extractJumps(l10n, invocation.output);

    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTappable(
              key: const Key('tool-invocation-card-header'),
              onPress: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      pending
                          ? FLucideIcons.hourglass
                          : FLucideIcons.circleCheck,
                      size: 16,
                      color: pending ? colors.mutedForeground : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: friendlyName,
                              style: context.theme.typography.sm.copyWith(
                                color: context.theme.colors.foreground,
                              ),
                            ),
                            if (summary != null) ...[
                              TextSpan(
                                text: '  ·  ',
                                style: context.theme.typography.xs.copyWith(
                                  color: context.theme.colors.mutedForeground,
                                ),
                              ),
                              TextSpan(
                                text: summary,
                                style: context.theme.typography.xs.copyWith(
                                  color: context.theme.colors.mutedForeground,
                                ),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                      size: AppIconSizes.h18,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            if (jumps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s12, 0, AppSpacing.s12, AppSpacing.s8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final jump in jumps)
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: () => _navigate(context, jump),
                        child: Text(jump.label),
                      ),
                  ],
                ),
              ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s12, 0, AppSpacing.s12, AppSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvBlock(
                      context,
                      l10n.aiChatToolInputLabel,
                      invocation.input,
                    ),
                    if (invocation.output != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      _resultBlock(context, l10n, invocation),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, _Jump jump) {
    switch (jump.kind) {
      case _JumpKind.asset:
        context.go(AppRoutes.wealthAsset(jump.id));
      case _JumpKind.account:
        context.go(AppRoutes.wealthAccount(jump.id));
      case _JumpKind.liability:
        context.go(AppRoutes.wealthLiability(jump.id));
      case _JumpKind.journalEntry:
        context.go(AppRoutes.activityEntry(jump.id));
      case _JumpKind.tradeJournal:
        // No per-entry detail page yet; Income Planner is the closest
        // surface that lists the same rows. The chip still carries the
        // id so a future detail route can swap in without reparsing.
        context.go(AppRoutes.planIncome);
    }
  }

  /// Renders the tool's output. Tries a tool-specific renderer first; falls
  /// back to pretty-printed JSON when no renderer is registered or when the
  /// renderer threw. The user can always toggle into raw JSON for debugging,
  /// and we force the raw view when the payload is too large for the inline
  /// renderer to be useful (see [isOversizedToolPayload]).
  Widget _resultBlock(
    BuildContext context,
    AppLocalizations l10n,
    ToolInvocation invocation,
  ) {
    final oversized = isOversizedToolPayload(
      invocation.name,
      invocation.output,
    );
    final body = (oversized || _showRawJson)
        ? null
        : renderToolOutput(context, invocation.name, invocation.output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.aiChatToolOutputLabel,
              style: context.theme.typography.xs2.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const Spacer(),
            if (body != null)
              FTappable(
                onPress: () => setState(() => _showRawJson = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.aiChatToolShowRawJson,
                    style: context.theme.typography.xs2.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
              )
            else if (_showRawJson &&
                renderToolOutput(context, invocation.name, invocation.output) !=
                    null)
              FTappable(
                onPress: () => setState(() => _showRawJson = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.aiChatToolShowCompactView,
                    style: context.theme.typography.xs2.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        if (body != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s8),
            decoration: BoxDecoration(
              color: context.theme.colors.background,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(
                color: context.theme.colors.border.withValues(alpha: 0.4),
              ),
            ),
            child: body,
          )
        else
          _rawJsonView(context, invocation.output),
      ],
    );
  }

  Widget _rawJsonView(BuildContext context, Object? value) {
    return _CodeBlock(text: _prettyJson(value));
  }

  Widget _kvBlock(BuildContext context, String label, Object? value) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall.fontSize,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: colors.mutedForeground,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        _CodeBlock(text: _prettyJson(value)),
      ],
    );
  }
}

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
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: colors.border, width: 1),
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
/// elsewhere — repeating it on per-tool rows muddies the signal.
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
    'get_fire_stress_tests' || 'simulate_fire_plan' => FLucideIcons.flaskConical,
    // Options income
    'get_options_income_opportunities' => FLucideIcons.piggyBank,
    'get_options_strategy_profile' => FLucideIcons.handshake,
    // Anything else — generic gear, never the AI sparkle (kept for
    // assistant-identity affordances elsewhere).
    _ => FLucideIcons.settings,
  };
}

/// Map a wire tool name (e.g. `get_holdings`) to a localized,
/// user-facing label (e.g. "查询持仓"). Unknown wires fall through to
/// the raw name — better than an opaque "unknown" placeholder, since
/// power users can still recognise the tool and report bugs.
String friendlyToolName(AppLocalizations l10n, String wireName) {
  return switch (wireName) {
    'get_holdings' => l10n.aiChatToolGetHoldings,
    'compute_xirr' => l10n.aiChatToolComputeXirr,
    'compute_net_worth' => l10n.aiChatToolComputeNetWorth,
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

enum _JumpKind {
  asset,
  account,
  liability,

  /// Ledger journal entry (`activity_entry/<id>`). Comes from
  /// `evidence.entity_table == 'journal_entries'`.
  journalEntry,

  /// Options trade journal row. Deep-links to the Income Planner page
  /// since there's no dedicated detail route.
  tradeJournal,
}

class _Jump {
  const _Jump({
    required this.kind,
    required this.id,
    required this.label,
    required this.icon,
  });
  final _JumpKind kind;
  final String id;
  final String label;
  final IconData icon;
}

/// Build the chip list shown above the expanded output.
///
/// Source-of-truth order:
/// 1. Structured `evidence` array on the output envelope
///    (`docs/roadmap-next.md` §3.4 — `EvidenceAnchor` contract). Newer
///    tools emit this and the mapping is exact (`entity_table` →
///    `_JumpKind`).
/// 2. Legacy heuristic walk that scrapes `asset_id` / `account_id` /
///    `liability_id` keys anywhere in the JSON tree. Kept for tools
///    that haven't migrated to evidence.
///
/// Surface up to four unique ids so the chip row stays readable.
List<_Jump> _extractJumps(AppLocalizations l10n, Object? output) {
  final seen = <String>{};
  final out = <_Jump>[];

  // (1) Structured evidence first — gives an exact entity_table mapping
  // and avoids the heuristic walk's false positives.
  if (output is Map) {
    final envelope = output.cast<String, Object?>();
    for (final anchor in readEvidence(envelope)) {
      if (out.length >= 4) break;
      final jump = _jumpFromEvidence(l10n, anchor);
      if (jump != null && seen.add('${jump.kind}:${jump.id}')) {
        out.add(jump);
      }
    }
  }
  void visit(Object? node) {
    if (out.length >= 4) return;
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          _JumpKind? kind;
          IconData? icon;
          String? label;
          switch (key) {
            case 'asset_id':
              kind = _JumpKind.asset;
              icon = FLucideIcons.wallet;
              label = l10n.aiChatToolJumpAsset(_shortId(value));
            case 'account_id':
              kind = _JumpKind.account;
              icon = FLucideIcons.userCircle;
              label = l10n.aiChatToolJumpAccount(_shortId(value));
            case 'liability_id':
              kind = _JumpKind.liability;
              icon = FLucideIcons.creditCard;
              label = l10n.aiChatToolJumpLiability(_shortId(value));
          }
          if (kind != null && seen.add('$kind:$value')) {
            out.add(_Jump(kind: kind, id: value, label: label!, icon: icon!));
            if (out.length >= 4) return;
          }
        }
        visit(value);
      }
    } else if (node is List) {
      for (final v in node) {
        visit(v);
        if (out.length >= 4) return;
      }
    }
  }

  visit(output);
  return out;
}

String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

/// Map one [EvidenceAnchor] to a chip the card can render + navigate.
/// Returns `null` for entity_tables that don't have a detail surface
/// yet (those anchors are dropped — better than rendering a dead chip).
_Jump? _jumpFromEvidence(AppLocalizations l10n, EvidenceAnchor anchor) {
  // Anchor's own label wins over the templated id when it's supplied —
  // tools that know a human label (e.g. "AAPL · cash_secured_put") have
  // already crafted the most useful chip text.
  final fallbackId = _shortId(anchor.entityId);
  String labelFor(String templated) =>
      anchor.label != null && anchor.label!.isNotEmpty
      ? anchor.label!
      : templated;

  switch (anchor.entityTable) {
    case 'assets':
      return _Jump(
        kind: _JumpKind.asset,
        id: anchor.entityId,
        label: labelFor(l10n.aiChatToolJumpAsset(fallbackId)),
        icon: FLucideIcons.wallet,
      );
    case 'accounts':
      return _Jump(
        kind: _JumpKind.account,
        id: anchor.entityId,
        label: labelFor(l10n.aiChatToolJumpAccount(fallbackId)),
        icon: FLucideIcons.userCircle,
      );
    case 'liabilities':
      return _Jump(
        kind: _JumpKind.liability,
        id: anchor.entityId,
        label: labelFor(l10n.aiChatToolJumpLiability(fallbackId)),
        icon: FLucideIcons.creditCard,
      );
    case 'journal_entries':
      return _Jump(
        kind: _JumpKind.journalEntry,
        id: anchor.entityId,
        label: labelFor(l10n.aiChatToolJumpJournalEntry(fallbackId)),
        icon: FLucideIcons.receipt,
      );
    case 'options_trade_journal':
      return _Jump(
        kind: _JumpKind.tradeJournal,
        id: anchor.entityId,
        label: labelFor(l10n.aiChatToolJumpTradeJournal(fallbackId)),
        icon: FLucideIcons.candlestickChart,
      );
    default:
      return null;
  }
}
