part of 'tool_invocation_card.dart';

EntityRouteRef _routeRefFor(_Jump jump) {
  return EntityRouteRef(
    entityTable: switch (jump.kind) {
      _JumpKind.asset => EntityRouteTables.assets,
      _JumpKind.account => EntityRouteTables.accounts,
      _JumpKind.liability => EntityRouteTables.liabilities,
      _JumpKind.journalEntry => EntityRouteTables.journalEntries,
      _JumpKind.tradeJournal => EntityRouteTables.optionsTradeJournal,
    },
    entityId: jump.id,
  );
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
///    (`docs/roadmap-next.md` §3.4 - `EvidenceAnchor` contract). Newer
///    tools emit this and the mapping is exact (`entity_table` ->
///    `_JumpKind`).
/// 2. Legacy heuristic walk that scrapes `asset_id` / `account_id` /
///    `liability_id` keys anywhere in the JSON tree. Kept for tools
///    that haven't migrated to evidence.
///
/// Surface up to four unique ids so the chip row stays readable.
List<_Jump> _extractJumps(AppLocalizations l10n, Object? output) {
  final seen = <String>{};
  final out = <_Jump>[];

  // (1) Structured evidence first - gives an exact entity_table mapping
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
/// yet (those anchors are dropped - better than rendering a dead chip).
_Jump? _jumpFromEvidence(AppLocalizations l10n, EvidenceAnchor anchor) {
  // Anchor's own label wins over the templated id when it's supplied -
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
