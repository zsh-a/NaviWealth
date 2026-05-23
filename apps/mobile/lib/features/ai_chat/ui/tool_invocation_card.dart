import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
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
      padding: const EdgeInsets.only(top: 8),
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
                          ? Icons.hourglass_empty
                          : Icons.check_circle_outline,
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
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            if (jumps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvBlock(
                      context,
                      l10n.aiChatToolInputLabel,
                      invocation.input,
                    ),
                    if (invocation.output != null) ...[
                      const SizedBox(height: 8),
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
        context.go(AppRoutes.accountAsset(jump.id));
      case _JumpKind.account:
        context.go(AppRoutes.accountListItem(jump.id));
      case _JumpKind.liability:
        context.go(AppRoutes.liability(jump.id));
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
        const SizedBox(height: 4),
        if (body != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.theme.colors.background,
              borderRadius: BorderRadius.circular(4),
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
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: colors.mutedForeground,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
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
      padding: const EdgeInsets.all(12),
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
          fontSize: 12,
          height: 1.45,
          color: colors.foreground,
        ),
      ),
    );
  }
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
