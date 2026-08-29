part of 'tool_invocation_card.dart';

EntityRouteRef _routeRefFor(_Jump jump) {
  return EntityRouteRef(entityTable: jump.entityTable, entityId: jump.id);
}

class _Jump {
  const _Jump({
    required this.entityTable,
    required this.id,
    required this.label,
  });
  final String entityTable;
  final String id;
  final String label;
}

/// Build the chip list shown above the expanded output.
///
/// Source-of-truth order:
/// 1. Structured `evidence` array on the output envelope
///    tools emit this and the app composition root resolves the owning
///    domain's route from `entity_table` + id.
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
      if (jump != null && seen.add('${jump.entityTable}:${jump.id}')) {
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
          String? entityTable;
          String? label;
          switch (key) {
            case 'asset_id':
              entityTable = EntityRouteTables.assets;
              label = l10n.aiChatToolJumpAsset(_shortId(value));
            case 'account_id':
              entityTable = EntityRouteTables.accounts;
              label = l10n.aiChatToolJumpAccount(_shortId(value));
            case 'liability_id':
              entityTable = EntityRouteTables.liabilities;
              label = l10n.aiChatToolJumpLiability(_shortId(value));
          }
          if (entityTable != null && seen.add('$entityTable:$value')) {
            out.add(_Jump(entityTable: entityTable, id: value, label: label!));
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
/// Returns `null` for entity tables that do not have an app-owned route.
_Jump? _jumpFromEvidence(AppLocalizations l10n, EvidenceAnchor anchor) {
  // Anchor's own label wins over the templated id when it's supplied -
  // tools that know a human label (e.g. "AAPL · cash_secured_put") have
  // already crafted the most useful chip text.
  final fallbackId = _shortId(anchor.entityId);
  String labelFor(String templated) =>
      anchor.label != null && anchor.label!.isNotEmpty
      ? anchor.label!
      : templated;

  final fallbackLabel = switch (anchor.entityTable) {
    'assets' => l10n.aiChatToolJumpAsset(fallbackId),
    'accounts' => l10n.aiChatToolJumpAccount(fallbackId),
    'liabilities' => l10n.aiChatToolJumpLiability(fallbackId),
    'journal_entries' => l10n.aiChatToolJumpJournalEntry(fallbackId),
    'options_trade_journal' => l10n.aiChatToolJumpTradeJournal(fallbackId),
    'health_metrics' ||
    'knowledge_notes' ||
    'knowledge_decisions' ||
    'execution_actions' ||
    'execution_plans' ||
    'execution_progress' => fallbackId,
    _ => null,
  };
  if (fallbackLabel == null) return null;
  return _Jump(
    entityTable: anchor.entityTable,
    id: anchor.entityId,
    label: labelFor(fallbackLabel),
  );
}
