import 'package:flutter/material.dart';

import '../../data/domain/entry_kind.dart';
import '../../l10n/gen/app_localizations.dart';

/// FIR-128 §1.1 — pill-shaped badge that surfaces the derived
/// [EntryKind] of a journal entry (icon + short label, colour-toned by
/// kind).
///
/// Stateless and theme-aware: colours come off [ColorScheme] so the
/// badge tracks light / dark / Glass automatically. Callers are
/// expected to render the badge tightly next to the entry summary
/// (list rows, AI proposal cards), so the contract here is "smallest
/// horizontal real estate that still reads at a glance".
class EntryKindBadge extends StatelessWidget {
  const EntryKindBadge({
    super.key,
    required this.classification,
    this.compact = false,
    this.labelOverride,
  });

  final EntryKindClassification classification;

  /// When `true`, the badge collapses to icon-only (use in list rows
  /// where horizontal space is at a premium).
  final bool compact;

  /// Optional caller-supplied label that replaces the default English
  /// short name. Passing `''` is honoured — the label disappears even
  /// if `compact` is `false`.
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visuals = _entryKindVisuals(classification, scheme);
    final l10n = AppLocalizations.of(context);

    final label = labelOverride ?? _localizeKind(classification.kind, l10n);
    final showLabel = !compact && label.isNotEmpty;

    return Semantics(
      container: true,
      label: l10n.entryKindSemanticLabel(
        _localizeKind(classification.kind, l10n),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visuals.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? 8 : 4,
            vertical: 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(visuals.icon, size: 14, color: visuals.foreground),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: visuals.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeVisuals {
  const _BadgeVisuals({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.defaultLabel,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String defaultLabel;
}

String _localizeKind(EntryKind kind, AppLocalizations l10n) {
  switch (kind) {
    case EntryKind.trade:
      return l10n.entryKindTrade;
    case EntryKind.transfer:
      return l10n.entryKindTransfer;
    case EntryKind.income:
      return l10n.entryKindIncome;
    case EntryKind.expense:
      return l10n.entryKindExpense;
    case EntryKind.payment:
      return l10n.entryKindPayment;
    case EntryKind.adjustment:
      return l10n.entryKindAdjustment;
    case EntryKind.opening:
      return l10n.entryKindOpening;
    case EntryKind.other:
      return l10n.entryKindEntry;
  }
}

_BadgeVisuals _entryKindVisuals(EntryKindClassification c, ColorScheme scheme) {
  switch (c.kind) {
    case EntryKind.trade:
      // Direction-aware icon. `null` (no cash leg) falls back to the
      // generic chart icon — never seen in the canonical builders but
      // possible if an external import lands a malformed JE.
      final icon = switch (c.isInflow) {
        true => Icons.trending_up,
        false => Icons.trending_down,
        null => Icons.show_chart,
      };
      return _BadgeVisuals(
        icon: icon,
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        defaultLabel: 'Trade',
      );
    case EntryKind.transfer:
      return _BadgeVisuals(
        icon: Icons.swap_horiz,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        defaultLabel: 'Transfer',
      );
    case EntryKind.income:
      return _BadgeVisuals(
        icon: Icons.south_west,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        defaultLabel: 'Income',
      );
    case EntryKind.expense:
      return _BadgeVisuals(
        icon: Icons.north_east,
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        defaultLabel: 'Expense',
      );
    case EntryKind.payment:
      return _BadgeVisuals(
        icon: Icons.payments,
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        defaultLabel: 'Payment',
      );
    case EntryKind.adjustment:
      return _BadgeVisuals(
        icon: Icons.call_split,
        background: scheme.surfaceContainerHigh,
        foreground: scheme.onSurface,
        defaultLabel: 'Adjustment',
      );
    case EntryKind.opening:
      return _BadgeVisuals(
        icon: Icons.flag_outlined,
        background: scheme.surfaceContainerHigh,
        foreground: scheme.onSurfaceVariant,
        defaultLabel: 'Opening',
      );
    case EntryKind.other:
      return _BadgeVisuals(
        icon: Icons.edit_note,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        defaultLabel: 'Entry',
      );
  }
}
