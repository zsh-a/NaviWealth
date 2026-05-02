import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../data/audit/domain_event.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/expense_category.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// FIR-127 / FIR-125 — "Change history" surface for a single expense.
///
/// Subscribes to the local audit ledger (`domain_event_log`) and renders
/// `created` / `field_changed` / `soft_deleted` events for the expense's
/// `transactions` row, oldest first. Account / category ids are resolved
/// to user-visible names via the corresponding stream providers so a row
/// reads "餐饮 → 交通" instead of two opaque UUIDs.
///
/// The widget paints nothing while no events are available *and* no header
/// has been rendered — i.e. the timeline gracefully no-ops if a caller
/// embeds it before any audit row exists. (See [showWhenEmpty] to override
/// for the create-without-history case.)
class ExpenseHistoryTimeline extends ConsumerWidget {
  const ExpenseHistoryTimeline({
    super.key,
    required this.expenseId,
    this.showWhenEmpty = true,
  });

  final String expenseId;

  /// When `false`, the widget collapses to a [SizedBox.shrink] if the
  /// timeline has zero events. The default is `true` because the form
  /// page wants to show "no changes recorded yet" so the user is not
  /// surprised by the empty section after a fresh entry.
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventsAsync = ref.watch(
      eventTimelineProvider((
        entityTable: 'transactions',
        entityId: expenseId,
      )),
    );
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(expenseCategoriesStreamProvider);

    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.s8),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => _SectionShell(
        title: l10n.expenseHistorySectionTitle,
        child: Text(l10n.expenseHistoryLoadError('$e')),
      ),
      data: (events) {
        if (events.isEmpty && !showWhenEmpty) {
          return const SizedBox.shrink();
        }
        final accountById = <String, Account>{
          for (final a in accountsAsync.asData?.value ?? const <Account>[])
            a.id: a,
        };
        final categoryById = <String, ExpenseCategory>{
          for (final c
              in categoriesAsync.asData?.value ?? const <ExpenseCategory>[])
            c.id: c,
        };
        final formatters = AppFormatters(
          locale: Localizations.localeOf(context),
        );
        if (events.isEmpty) {
          return _SectionShell(
            title: l10n.expenseHistorySectionTitle,
            child: Text(
              l10n.expenseHistoryEmpty,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return _SectionShell(
          title: l10n.expenseHistorySectionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < events.length; i++) ...[
                if (i > 0) const Divider(height: Spacing.s16),
                _EventTile(
                  event: events[i],
                  accountById: accountById,
                  categoryById: categoryById,
                  formatters: formatters,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s8),
            child,
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.accountById,
    required this.categoryById,
    required this.formatters,
  });

  final DomainEvent event;
  final Map<String, Account> accountById;
  final Map<String, ExpenseCategory> categoryById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _kindChip(context, event.kind),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Text(
                formatters.dateTime(event.recordedAt.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.s4),
        ..._renderRows(context, l10n),
        if (event.reason != null && event.reason!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4),
            child: Text(
              l10n.expenseHistoryReasonLabel(event.reason!),
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _kindChip(BuildContext context, DomainEventKind kind) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, fg, bg) = switch (kind) {
      DomainEventKind.created => (
        l10n.expenseHistoryEventCreated,
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
      ),
      DomainEventKind.fieldChanged => (
        l10n.expenseHistoryEventChanged,
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      DomainEventKind.softDeleted => (
        l10n.expenseHistoryEventDeleted,
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      DomainEventKind.restored => (
        l10n.expenseHistoryEventRestored,
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Spacing.s12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  List<Widget> _renderRows(BuildContext context, AppLocalizations l10n) {
    switch (event.kind) {
      case DomainEventKind.created:
        return _createdRows(context, l10n);
      case DomainEventKind.fieldChanged:
        return _diffRows(context, l10n);
      case DomainEventKind.softDeleted:
        return [
          Text(
            l10n.expenseHistoryDeletedBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
      case DomainEventKind.restored:
        return [
          Text(
            l10n.expenseHistoryRestoredBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
    }
  }

  /// `created` rows give the user a snapshot of the seed values so they
  /// don't have to read a row of bare field keys. Fields are rendered
  /// using the same formatters as the diff path so amounts, dates, and
  /// resolved names look identical between create and update entries.
  List<Widget> _createdRows(BuildContext context, AppLocalizations l10n) {
    final after = event.after ?? const <String, Object?>{};
    final rows = <Widget>[];
    final amountValue = _resolveAmount(after);
    if (amountValue != null) {
      rows.add(
        _kvRow(
          context,
          label: l10n.expenseHistoryFieldAmount,
          value: _formatAmount(after, amountValue),
        ),
      );
    }
    final categoryId = _resolveCategoryId(after);
    if (categoryId != null) {
      rows.add(
        _kvRow(
          context,
          label: l10n.expenseHistoryFieldCategory,
          value: _categoryLabel(categoryId, l10n),
        ),
      );
    }
    final accountId = after['account_id'];
    if (accountId is String) {
      rows.add(
        _kvRow(
          context,
          label: l10n.expenseHistoryFieldAccount,
          value: _accountLabel(accountId, l10n),
        ),
      );
    }
    final tradeDate = _parseDate(after['trade_date']);
    if (tradeDate != null) {
      rows.add(
        _kvRow(
          context,
          label: l10n.expenseHistoryFieldDate,
          value: formatters.date(tradeDate.toLocal()),
        ),
      );
    }
    final note = after['note'];
    if (note is String && note.isNotEmpty) {
      rows.add(
        _kvRow(
          context,
          label: l10n.expenseHistoryFieldNote,
          value: note,
        ),
      );
    }
    if (rows.isEmpty) {
      return [
        Text(
          l10n.expenseHistoryCreatedBody,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    return rows;
  }

  List<Widget> _diffRows(BuildContext context, AppLocalizations l10n) {
    final before = event.before ?? const <String, Object?>{};
    final after = event.after ?? const <String, Object?>{};
    final keys = after.keys.toList();
    if (keys.isEmpty) return const [];
    return [
      for (final key in keys)
        _diffRow(
          context,
          l10n,
          key: key,
          before: before[key],
          after: after[key],
        ),
    ];
  }

  Widget _diffRow(
    BuildContext context,
    AppLocalizations l10n, {
    required String key,
    required Object? before,
    required Object? after,
  }) {
    final label = _fieldLabel(key, l10n);
    final beforeText = _fieldValue(key, before, l10n);
    final afterText = _fieldValue(key, after, l10n);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s2),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(text: beforeText),
            const TextSpan(text: '  →  '),
            TextSpan(
              text: afterText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s2),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _fieldLabel(String key, AppLocalizations l10n) {
    switch (key) {
      case 'amount':
        return l10n.expenseHistoryFieldAmount;
      case 'currency':
        return l10n.expenseHistoryFieldCurrency;
      case 'account_id':
        return l10n.expenseHistoryFieldAccount;
      case 'category_id':
        return l10n.expenseHistoryFieldCategory;
      case 'trade_date':
        return l10n.expenseHistoryFieldDate;
      case 'note':
        return l10n.expenseHistoryFieldNote;
      case 'tags':
        return l10n.expenseHistoryFieldTags;
      default:
        return key;
    }
  }

  String _fieldValue(String key, Object? raw, AppLocalizations l10n) {
    if (raw == null) return l10n.expenseHistoryEmptyValue;
    switch (key) {
      case 'amount':
        final dec = Decimal.tryParse('$raw');
        if (dec == null) return '$raw';
        return formatters.number(dec.toDouble());
      case 'trade_date':
        final parsed = _parseDate(raw);
        if (parsed == null) return '$raw';
        return formatters.date(parsed.toLocal());
      case 'account_id':
        return _accountLabel('$raw', l10n);
      case 'category_id':
        return _categoryLabel('$raw', l10n);
      case 'tags':
        if (raw is List) {
          if (raw.isEmpty) return l10n.expenseHistoryEmptyValue;
          return raw.join(', ');
        }
        return '$raw';
      default:
        if (raw is String && raw.isEmpty) {
          return l10n.expenseHistoryEmptyValue;
        }
        return '$raw';
    }
  }

  String _accountLabel(String id, AppLocalizations l10n) {
    final account = accountById[id];
    if (account != null) return account.name;
    return l10n.expenseHistoryUnknownReference;
  }

  String _categoryLabel(String id, AppLocalizations l10n) {
    final category = categoryById[id];
    if (category != null) return category.name;
    return l10n.expenseHistoryUnknownReference;
  }

  /// `created` rows reuse the outbox-fields shape, where the magnitude is
  /// stored as a signed `quantity`. Audit/UI always shows the positive
  /// magnitude, so we negate it here to match the diff path's `'amount'`
  /// key.
  Decimal? _resolveAmount(Map<String, Object?> after) {
    final amountRaw = after['amount'] ?? after['quantity'];
    if (amountRaw == null) return null;
    final dec = Decimal.tryParse('$amountRaw');
    if (dec == null) return null;
    if (after.containsKey('amount')) return dec;
    return -dec;
  }

  String _formatAmount(Map<String, Object?> after, Decimal amount) {
    final number = formatters.number(amount.toDouble());
    final currency = after['currency'];
    if (currency is String && currency.isNotEmpty) {
      return '$number $currency';
    }
    return number;
  }

  String? _resolveCategoryId(Map<String, Object?> after) {
    final direct = after['category_id'];
    if (direct is String) return direct;
    final blob = after['expense_metadata_json'];
    if (blob is String) {
      // Cheap, format-tolerant extraction so we don't pull in a JSON
      // dependency just for the create-snapshot label.
      final match = RegExp('"categoryId"\\s*:\\s*"([^"]+)"').firstMatch(blob);
      if (match != null) return match.group(1);
    }
    return null;
  }

  DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse('$raw');
  }
}
