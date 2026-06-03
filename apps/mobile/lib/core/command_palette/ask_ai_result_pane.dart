/// §5.10 Layer 1 — in-place structured answer for the command palette
/// overlay.
///
/// When the user types a natural-language question into the palette, the
/// pane runs the same local pipeline that powers the AI chat fast-path
/// ([parseNlQuery] → [QueryPlanExecutor] → [QueryResult]) and renders the
/// result *inline* above the navigation/command list. The user never has
/// to leave the overlay to see an answer for the kinds of questions the
/// device can resolve offline.
///
/// What the pane never does:
///   * Send anything to a cloud model (that path lives in
///     `/settings/ai-history`).
///   * Execute irreversible side effects — transfer / order / delete
///     phrases short-circuit to a guidance card (§5.10.6).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai/local/skills/finance_query_plan.dart';
import '../ai/local/skills/nl_to_query_plan.dart';
import '../ai/local/skills/query_plan_executor.dart';

/// State the [AskAiResultPane] cycles through as the user's query changes.
enum _PaneStatus { idle, loading, irreversible, noMatch, result, error }

/// In-place answer pane embedded between the search field and the
/// command list. Self-contained: pass it a [query] and a
/// [QueryPlanExecutor]; the pane handles parsing, running, and rendering.
class AskAiResultPane extends StatefulWidget {
  const AskAiResultPane({
    super.key,
    required this.query,
    required this.executor,
    required this.now,
    this.onContinueInChat,
  });

  /// Trimmed user query. Empty/null is not allowed — callers should
  /// simply not mount the pane when the search field is empty.
  final String query;

  /// Adapter that runs a [FinanceQueryPlan]. The command palette wires
  /// this from `driftQueryPlanExecutorProvider`; tests inject an
  /// in-memory executor.
  final QueryPlanExecutor executor;

  /// Anchors relative time references ("上月", "近 30 天") inside
  /// [parseNlQuery]. Production reads `DateTime.now()`; tests freeze it.
  final DateTime now;

  /// Tapping the "continue in chat" link pops the palette and routes to
  /// `/settings/ai-history` with the query pre-filled. Optional so the
  /// pane stays decoupled from go_router in tests.
  final void Function(String query)? onContinueInChat;

  @override
  State<AskAiResultPane> createState() => _AskAiResultPaneState();
}

class _AskAiResultPaneState extends State<AskAiResultPane> {
  _PaneStatus _status = _PaneStatus.idle;
  QueryResult? _result;
  String? _errorMessage;
  int _runSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_runForQuery(widget.query));
  }

  @override
  void didUpdateWidget(AskAiResultPane old) {
    super.didUpdateWidget(old);
    if (widget.query != old.query) {
      unawaited(_runForQuery(widget.query));
    }
  }

  Future<void> _runForQuery(String raw) async {
    final seq = ++_runSeq;
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() => _status = _PaneStatus.idle);
      return;
    }
    if (_detectsIrreversible(query)) {
      setState(() {
        _status = _PaneStatus.irreversible;
        _result = null;
        _errorMessage = null;
      });
      return;
    }
    final plan = parseNlQuery(query, now: widget.now);
    if (plan == null) {
      setState(() {
        _status = _PaneStatus.noMatch;
        _result = null;
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _status = _PaneStatus.loading;
      _result = null;
      _errorMessage = null;
    });
    try {
      final result = await widget.executor.run(plan);
      if (!mounted || seq != _runSeq) return;
      setState(() {
        _status = _PaneStatus.result;
        _result = result;
      });
    } catch (e) {
      if (!mounted || seq != _runSeq) return;
      setState(() {
        _status = _PaneStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: colors.secondary,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StatusBadge(label: l10n.askAiResultLocalBadge),
          const SizedBox(height: AppSpacing.s8),
          _buildBody(l10n),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    switch (_status) {
      case _PaneStatus.idle:
      case _PaneStatus.loading:
        return _SkeletonRow();
      case _PaneStatus.irreversible:
        return _GuidanceText(
          icon: FLucideIcons.lock,
          message: l10n.askAiResultIrreversibleBlocked,
        );
      case _PaneStatus.noMatch:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _GuidanceText(
              icon: FLucideIcons.info,
              message: l10n.askAiResultNoLocalMatch,
            ),
            if (widget.onContinueInChat != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s8),
              _ContinueInChatLink(
                label: l10n.askAiResultContinueInChat,
                onTap: () => widget.onContinueInChat!(widget.query.trim()),
              ),
            ],
          ],
        );
      case _PaneStatus.error:
        return _GuidanceText(
          icon: FLucideIcons.circleAlert,
          message: l10n.askAiResultError(_errorMessage ?? '?'),
        );
      case _PaneStatus.result:
        return _ResultView(result: _result!);
    }
  }
}

// ── irreversible-keyword detector ───────────────────────────────────
//
// §5.10.6 — command palette never executes transfers / orders /
// account deletion via NL. The detector is intentionally generous: a
// false positive is cheap (we just show a guidance card), a false
// negative would let the parser try to handle a write-shaped query.
bool _detectsIrreversible(String raw) {
  final q = raw.toLowerCase();
  const triggers = <String>[
    // transfer
    '转账', '转 ', '划转', '汇款', 'transfer ', 'send to ', 'pay ',
    // order placement (broker / exchange)
    '下单', '买入 ', '卖出 ', 'buy ', 'sell ',
    // account / record deletion
    '删除账户', '注销账户', '删除 ', 'delete account', 'remove account',
    'cancel subscription',
  ];
  for (final t in triggers) {
    if (q.contains(t)) return true;
  }
  return false;
}

// ── presentation pieces ─────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: colors.mutedForeground,
            fontFeatures: TypographyTokens.tabularFigures,
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}

class _GuidanceText extends StatelessWidget {
  const _GuidanceText({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppIconSizes.sm, color: colors.mutedForeground),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            message,
            style: context.theme.typography.sm.copyWith(
              color: colors.foreground,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueInChatLink extends StatelessWidget {
  const _ContinueInChatLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: Text(
        label,
        style: context.theme.typography.sm.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary,
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});
  final QueryResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final summary = result.summary;
    final rows = result.rows;
    final preview = rows.take(_maxPreviewRows).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _planTitleFor(result.plan, l10n),
          style: context.theme.typography.sm.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (summary != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s4),
          _SummaryLine(summary: summary, planKind: result.plan.kind),
        ],
        if (preview.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Text(
              l10n.askAiResultEmpty,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: AppSpacing.s8),
          for (final row in preview)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: _ResultRow(row: row),
            ),
          if (rows.length > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.askAiResultMoreRows(rows.length - preview.length),
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ),
        ],
        if (result.note != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s8),
          Text(
            result.note!,
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }

  static const int _maxPreviewRows = 5;
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.summary, required this.planKind});
  final QuerySummary summary;
  final String planKind;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final amount = summary.totalAbsAmountMinor / 100.0;
    final showAmount =
        planKind == 'spending_by_category' ||
        planKind == 'transactions_filter' ||
        planKind == 'refund_matching' ||
        planKind == 'subscription_list';
    return Row(
      children: <Widget>[
        if (showAmount) ...<Widget>[
          MoneyText(
            amount: amount,
            currencyCode: summary.currency,
            style: TypographyTokens.numericMono.copyWith(
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
        ],
        if (summary.rowCount != null)
          Text(
            l10n.askAiResultRowCount(summary.rowCount!),
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
              fontFeatures: TypographyTokens.tabularFigures,
            ),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.row});
  final QueryRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final amountMinor =
        row.values['amount_minor'] ?? row.values['median_amount_minor'];
    final currency = row.values['currency'] as String?;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            row.label,
            style: context.theme.typography.sm.copyWith(
              color: colors.foreground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (amountMinor is int && currency != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s8),
          MoneyText(
            amount: amountMinor.abs() / 100.0,
            currencyCode: currency,
            style: TypographyTokens.numericMono.copyWith(
              color: colors.foreground,
            ),
          ),
        ],
      ],
    );
  }
}

String _planTitleFor(FinanceQueryPlan plan, AppLocalizations l10n) {
  switch (plan.kind) {
    case 'spending_by_category':
      return l10n.askAiResultTitleSpending;
    case 'transactions_filter':
      return l10n.askAiResultTitleTransactions;
    case 'net_worth_trend':
      return l10n.askAiResultTitleNetWorth;
    case 'subscription_list':
      return l10n.askAiResultTitleSubscriptions;
    case 'refund_matching':
      return l10n.askAiResultTitleRefunds;
    default:
      return l10n.askAiResultTitleGeneric;
  }
}
