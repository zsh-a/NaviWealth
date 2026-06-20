import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/account_l10n.dart';
import '../data/activity_feed_provider.dart';

/// Activity timeline filter sheet — dimensions the inline kind chip row
/// can't express: **date range** + **per-account multi-select**.
///
/// Kind selection is intentionally absent here even though the
/// underlying `ActivityFeedQuery` carries a `kinds` field — that's
/// already covered by the inline chip row at the top of the timeline.
/// Showing it twice was the original "redundant content" complaint, so
/// the sheet now stays narrowly focused on the two dimensions inline
/// chips can't reach.
///
/// Edits apply live (the timeline rebuilds via Riverpod the moment the
/// query changes); there is no Save button. Dismiss the sheet by
/// dragging it down or tapping outside. The Clear action in the sheet
/// header zeroes the date range + accounts (kind chips stay where the
/// user left them in the inline row).
class ActivityFeedFilterSheet extends ConsumerWidget {
  const ActivityFeedFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showAppSheet<void>(
      context: context,
      title: l10n.activityFeedFilterTitle,
      builder: (_) => const ActivityFeedFilterSheet(),
      actions: [
        Consumer(
          builder: (ctx, ref, _) => _HeaderTextAction(
            label: l10n.activityFeedFilterClear,
            onPress: () {
              // Zero the dimensions this sheet owns. Kind selection
              // stays untouched — that's the inline row's domain.
              final controller = ref.read(activityFeedQueryProvider.notifier);
              controller.mutateQuery(
                (q) =>
                    q.copyWith(dateRange: null, accountIds: const <String>{}),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final activeRange = _activeRangeOf(query.dateRange);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetSectionLabel(text: l10n.activityFeedFilterDateRange),
        _DateRangeRow(
          active: activeRange,
          onPick: (range) => controller.mutateQuery(
            (q) => q.copyWith(dateRange: _rangeFor(range)),
          ),
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
        _SheetSectionLabel(text: l10n.activityFeedFilterAccount),
        if (accounts.isEmpty)
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final account in accounts)
                    _AccountFilterRow(
                      account: account,
                      selected: query.accountIds.contains(account.id),
                      onToggle: () {
                        controller.mutateQuery((q) {
                          final ids = {...q.accountIds};
                          ids.contains(account.id)
                              ? ids.remove(account.id)
                              : ids.add(account.id);
                          return q.copyWith(accountIds: ids);
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _DateRange { thisWeek, thisMonth, lastMonth, thisYear, custom }

DateTimeRange? _rangeFor(_DateRange r) {
  final now = DateTime.now();
  switch (r) {
    case _DateRange.thisWeek:
      final start = now.subtract(Duration(days: now.weekday - 1));
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
  return '${fmt(r.start)} → ${fmt(r.end.subtract(const Duration(days: 1)))}';
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({required this.active, required this.onPick});

  final _DateRange? active;
  final ValueChanged<_DateRange> onPick;

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
        for (final (range, label) in entries)
          AppFilterChip(
            label: label,
            active: active == range,
            onPress: () => onPick(range),
          ),
        // Custom date pickers feel out-of-place inside a quick-filter
        // sheet on mobile, so we surface a "Pick range…" pill that
        // routes to the platform date range picker.
        AppFilterChip(
          label: l10n.activityFeedFilterRangeCustom,
          active: active == _DateRange.custom,
          onPress: () => _pickCustom(context, onPick),
        ),
      ],
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    ValueChanged<_DateRange> onPick,
  ) async {
    final now = DateTime.now();
    // Capture the container before await so the post-await check
    // doesn't need a reanchored BuildContext.
    final container = ProviderScope.containerOf(context);
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month, now.day + 1),
      ),
    );
    if (result != null) {
      container
          .read(activityFeedQueryProvider.notifier)
          .mutateQuery((q) => q.copyWith(dateRange: result));
    }
  }
}

class _HeaderTextAction extends StatelessWidget {
  const _HeaderTextAction({required this.label, required this.onPress});

  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        child: Text(
          label,
          style: context.labelStyle.copyWith(
            color: context.theme.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s0,
        AppSpacing.s0,
        AppSpacing.s0,
        AppSpacing.s8,
      ),
      child: Text(
        text.toUpperCase(),
        style: context.microLabelStyle.copyWith(
          color: context.theme.colors.mutedForeground,
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
    return FTappable(
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
                style: context.theme.typography.sm,
              ),
            ),
            FCheckbox(value: selected, onChange: (_) => onToggle()),
          ],
        ),
      ),
    );
  }
}
