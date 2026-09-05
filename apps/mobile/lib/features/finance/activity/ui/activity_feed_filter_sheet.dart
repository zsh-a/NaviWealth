import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../shared/l10n/account_l10n.dart';
import '../../shared/l10n/entry_kind_labels.dart';
import '../data/activity_feed_provider.dart';
import '../data/activity_feed_query.dart';

/// Activity timeline filter sheet with draft-based edits.
///
/// The feed only changes when the user applies the draft, avoiding repeated
/// refreshes behind the sheet while chips are being selected.
class ActivityFeedFilterSheet extends ConsumerWidget {
  const ActivityFeedFilterSheet({super.key, required this.draft});

  final ValueNotifier<ActivityFeedQuery> draft;

  static Future<void> show(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context);
    final draft = ValueNotifier<ActivityFeedQuery>(
      container.read(activityFeedQueryProvider),
    );
    try {
      await showAppSheet<void>(
        context: context,
        title: l10n.activityFeedFilterTitle,
        maxHeightFactor: 0.9,
        builder: (_) => ActivityFeedFilterSheet(draft: draft),
        actions: [
          _HeaderTextAction(
            label: l10n.activityFeedFilterClear,
            onPress: () {
              draft.value = draft.value.copyWith(
                kinds: const <ActivityKind>{},
                dateRange: null,
                accountIds: const <String>{},
              );
            },
          ),
        ],
        footer: _FilterFooter(
          onApply: (sheetContext) {
            final next = draft.value;
            container
                .read(activityFeedQueryProvider.notifier)
                .mutateQuery(
                  (current) => current.copyWith(
                    dateRange: next.dateRange,
                    kinds: Set<ActivityKind>.unmodifiable(next.kinds),
                    accountIds: Set<String>.unmodifiable(next.accountIds),
                  ),
                );
            Navigator.of(sheetContext).pop();
          },
        ),
      );
    } finally {
      draft.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? const <Account>[];
    return ValueListenableBuilder<ActivityFeedQuery>(
      valueListenable: draft,
      builder: (context, query, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetSectionLabel(l10n.activityFeedFilterDateRange),
          _DateRangeRow(
            active: _activeRangeOf(query.dateRange),
            current: query.dateRange,
            onChanged: (range) =>
                draft.value = query.copyWith(dateRange: range),
          ),
          if (query.dateRange != null)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.s6,
                left: AppSpacing.s4,
              ),
              child: Text(
                _formatRange(l10n, query.dateRange!),
                style: context.captionStyle,
              ),
            ),
          const SizedBox(height: AppSpacing.s20),
          AppSheetSectionLabel(l10n.activityFeedFilterKind),
          _KindFilterRow(
            selected: query.kinds,
            onChanged: (kinds) => draft.value = query.copyWith(kinds: kinds),
          ),
          const SizedBox(height: AppSpacing.s20),
          AppSheetSectionLabel(l10n.activityFeedFilterAccount),
          if (accountsAsync.hasError)
            AppStatusBanner(
              kind: AppStatusKind.error,
              compact: true,
              message: l10n.activityAccountsUnavailable,
              action: FButton(
                variant: FButtonVariant.ghost,
                onPress: () => ref.invalidate(accountsStreamProvider),
                child: Text(l10n.commonRetry),
              ),
            )
          else if (!accountsAsync.hasValue)
            Text(l10n.commonLoading, style: context.captionStyle)
          else if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.s4,
                bottom: AppSpacing.s8,
              ),
              child: Text(
                l10n.activityFeedFilterAccountEmpty,
                style: context.captionStyle,
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final account in accounts)
                  _AccountFilterRow(
                    account: account,
                    selected: query.accountIds.contains(account.id),
                    onToggle: () {
                      final ids = {...query.accountIds};
                      ids.contains(account.id)
                          ? ids.remove(account.id)
                          : ids.add(account.id);
                      draft.value = query.copyWith(accountIds: ids);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilterFooter extends StatelessWidget {
  const _FilterFooter({required this.onApply});

  final ValueChanged<BuildContext> onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheetFooter(
      submitLabel: l10n.activityFeedFilterApply,
      onSubmit: () => onApply(context),
      cancelLabel: l10n.commonCancel,
    );
  }
}

class _KindFilterRow extends StatelessWidget {
  const _KindFilterRow({required this.selected, required this.onChanged});

  final Set<ActivityKind> selected;
  final ValueChanged<Set<ActivityKind>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const kinds = <ActivityKind>[
      ActivityKind.income,
      ActivityKind.expense,
      ActivityKind.transfer,
      ActivityKind.trade,
    ];
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        AppFilterChip(
          label: l10n.activityFilterChipAll,
          active: selected.isEmpty,
          onPress: () => onChanged(const <ActivityKind>{}),
        ),
        for (final kind in kinds)
          AppFilterChip(
            label: entryKindLabel(l10n, entryKindFromActivityKind(kind)),
            active: selected.contains(kind),
            onPress: () {
              final next = {...selected};
              next.contains(kind) ? next.remove(kind) : next.add(kind);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Convert picker-inclusive calendar dates to the feed's half-open interval.
DateTimeRange activityQueryRange(DateTimeRange range) => DateTimeRange(
  start: DateTime(range.start.year, range.start.month, range.start.day),
  end: DateTime(range.end.year, range.end.month, range.end.day + 1),
);

DateTimeRange activityPickerRange(DateTimeRange range) => DateTimeRange(
  start: range.start,
  end: DateTime(range.end.year, range.end.month, range.end.day - 1),
);

enum _DateRange { thisWeek, thisMonth, lastMonth, thisYear, custom }

DateTimeRange? _rangeFor(_DateRange r) {
  final now = DateTime.now();
  switch (r) {
    case _DateRange.thisWeek:
      final start = DateTime(now.year, now.month, now.day - now.weekday + 1);
      return DateTimeRange(
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(now.year, now.month, now.day + 1),
      );
    case _DateRange.thisMonth:
      return DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    case _DateRange.lastMonth:
      return DateTimeRange(
        start: DateTime(now.year, now.month - 1),
        end: DateTime(now.year, now.month),
      );
    case _DateRange.thisYear:
      return DateTimeRange(
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
      );
    case _DateRange.custom:
      return null;
  }
}

_DateRange? _activeRangeOf(DateTimeRange? r) {
  if (r == null) return null;
  for (final preset in [
    _DateRange.thisWeek,
    _DateRange.thisMonth,
    _DateRange.lastMonth,
    _DateRange.thisYear,
  ]) {
    final candidate = _rangeFor(preset);
    if (candidate != null &&
        candidate.start == r.start &&
        candidate.end == r.end) {
      return preset;
    }
  }
  return _DateRange.custom;
}

String _formatRange(AppLocalizations l10n, DateTimeRange r) {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${fmt(r.start)} → ${fmt(activityPickerRange(r).end)}';
}

String activityFeedDateRangeLabel(AppLocalizations l10n, DateTimeRange? range) {
  if (range == null) return l10n.activityFeedFilterAllDates;
  return switch (_activeRangeOf(range)) {
    _DateRange.thisWeek => l10n.activityFeedFilterRangeThisWeek,
    _DateRange.thisMonth => l10n.activityFeedFilterRangeThisMonth,
    _DateRange.lastMonth => l10n.activityFeedFilterRangeLastMonth,
    _DateRange.thisYear => l10n.activityFeedFilterRangeThisYear,
    _DateRange.custom || null => _formatRange(l10n, range),
  };
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({
    required this.active,
    required this.current,
    required this.onChanged,
  });

  final _DateRange? active;
  final DateTimeRange? current;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(_DateRange, String)>[
      (_DateRange.thisWeek, l10n.activityFeedFilterRangeThisWeek),
      (_DateRange.thisMonth, l10n.activityFeedFilterRangeThisMonth),
      (_DateRange.lastMonth, l10n.activityFeedFilterRangeLastMonth),
      (_DateRange.thisYear, l10n.activityFeedFilterRangeThisYear),
    ];
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        AppFilterChip(
          label: l10n.activityFeedFilterAllDates,
          active: active == null,
          onPress: () => onChanged(null),
        ),
        for (final (range, label) in entries)
          AppFilterChip(
            label: label,
            active: active == range,
            onPress: () {
              AppInteraction.signal(AppInteractionIntent.select);
              onChanged(_rangeFor(range));
            },
          ),
        // Custom date pickers feel out-of-place inside a quick-filter
        // sheet on mobile, so we surface a "Pick range…" pill that
        // routes to the platform date range picker.
        AppFilterChip(
          label: l10n.activityFeedFilterRangeCustom,
          active: active == _DateRange.custom,
          onPress: () => _pickCustom(context),
        ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange:
          (current == null ? null : activityPickerRange(current!)) ??
          DateTimeRange(
            start: DateTime(now.year, now.month),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (result != null) onChanged(activityQueryRange(result));
  }
}

class _HeaderTextAction extends StatelessWidget {
  const _HeaderTextAction({required this.label, required this.onPress});

  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        child: Text(
          label,
          style: context.mediumLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _AccountFilterRow extends StatelessWidget {
  const _AccountFilterRow({
    required this.account,
    required this.selected,
    required this.onToggle,
  });

  final Account account;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                localizedAccountName(AppLocalizations.of(context), account),
                style: context.theme.typography.body.sm,
              ),
            ),
            FCheckbox(
              value: selected,
              onChange: (_) {
                AppInteraction.signal(AppInteractionIntent.select);
                onToggle();
              },
            ),
          ],
        ),
      ),
    );
  }
}
