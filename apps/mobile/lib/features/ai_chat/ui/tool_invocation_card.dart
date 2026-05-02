import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/chat_models.dart';

/// Collapsible card surfacing one tool invocation. Header shows the
/// human-friendly tool name + a one-line summary; the body (when
/// expanded) renders pretty-printed JSON for the input and output
/// payloads so the user can see exactly what the model queried.
///
/// When the tool's output references known entities (asset_id,
/// transaction_id, account_id), we surface a "跳到资产" / "跳到交易"
/// chip so the user can jump straight to the relevant detail page.
class ToolInvocationCard extends StatefulWidget {
  const ToolInvocationCard({super.key, required this.invocation});

  final ToolInvocation invocation;

  @override
  State<ToolInvocationCard> createState() => _ToolInvocationCardState();
}

class _ToolInvocationCardState extends State<ToolInvocationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final invocation = widget.invocation;
    final pending = invocation.output == null;
    final friendlyName = _friendlyToolName(l10n, invocation.name);
    final summary = _summarizeInput(invocation.input);
    final jumps = _extractJumps(l10n, invocation.output);

    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: Radii.brSm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: Radii.brSm,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.s12,
                vertical: Spacing.s8,
              ),
              child: Row(
                children: [
                  Icon(
                    pending
                        ? Icons.hourglass_empty
                        : Icons.check_circle_outline,
                    size: 16,
                    color: pending ? cs.tertiary : cs.primary,
                  ),
                  const SizedBox(width: Spacing.s8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: friendlyName,
                            style: tt.labelLarge?.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                          if (summary != null) ...[
                            TextSpan(
                              text: '  ·  ',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            TextSpan(
                              text: summary,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
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
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (jumps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.s12,
                0,
                Spacing.s12,
                Spacing.s8,
              ),
              child: Wrap(
                spacing: Spacing.s8,
                runSpacing: Spacing.s4,
                children: [
                  for (final jump in jumps)
                    ActionChip(
                      avatar: Icon(jump.icon, size: 16),
                      label: Text(jump.label),
                      onPressed: () => _navigate(context, jump),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.s12,
                0,
                Spacing.s12,
                Spacing.s12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kvBlock(context, l10n.aiChatToolInputLabel, invocation.input),
                  if (invocation.output != null) ...[
                    const SizedBox(height: Spacing.s8),
                    _kvBlock(
                      context,
                      l10n.aiChatToolOutputLabel,
                      invocation.output,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, _Jump jump) {
    switch (jump.kind) {
      case _JumpKind.asset:
        context.go('/assets/${Uri.encodeComponent(jump.id)}');
      case _JumpKind.account:
        context.go('/accounts/${Uri.encodeComponent(jump.id)}');
      case _JumpKind.liability:
        context.go('/assets/liabilities/${Uri.encodeComponent(jump.id)}');
    }
  }

  Widget _kvBlock(BuildContext context, String label, Object? value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.s4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.s8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: Radii.brXs,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: SelectableText(
            _prettyJson(value),
            style: tt.bodySmall?.copyWith(
              fontFamily: TypographyTokens.fontFamilyMono,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

String _friendlyToolName(AppLocalizations l10n, String wireName) {
  return switch (wireName) {
    'get_holdings' => l10n.aiChatToolGetHoldings,
    'get_transactions' => l10n.aiChatToolGetTransactions,
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

enum _JumpKind { asset, account, liability }

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

/// Walk the tool output looking for `asset_id` / `account_id` /
/// `liability_id` fields (anywhere in the tree, including inside
/// arrays). Surface up to four unique ids so the chip row stays
/// readable.
List<_Jump> _extractJumps(AppLocalizations l10n, Object? output) {
  final seen = <String>{};
  final out = <_Jump>[];
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
              icon = Icons.account_balance_wallet_outlined;
              label = l10n.aiChatToolJumpAsset(_shortId(value));
            case 'account_id':
              kind = _JumpKind.account;
              icon = Icons.account_box_outlined;
              label = l10n.aiChatToolJumpAccount(_shortId(value));
            case 'liability_id':
              kind = _JumpKind.liability;
              icon = Icons.credit_card_outlined;
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
