part of 'trend_card.dart';

class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(dashboardSelectedRangeProvider);
    return SegmentedRow<DashboardRangePreset>(
      options: DashboardRangePreset.values,
      value: selected,
      labelOf: (preset) => _rangeLabel(l10n, preset),
      onChanged: (preset) => _select(context, ref, preset),
    );
  }

  void _select(
    BuildContext context,
    WidgetRef ref,
    DashboardRangePreset preset,
  ) {
    if (preset == DashboardRangePreset.custom) {
      _pickCustomRange(context, ref);
      return;
    }
    ref.read(dashboardCustomRangeProvider.notifier).state = null;
    ref.read(dashboardSelectedRangeProvider.notifier).state = preset;
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initialEnd = ref.read(dashboardCustomRangeProvider)?.to ?? now;
    final initialStart =
        ref.read(dashboardCustomRangeProvider)?.from ??
        now.subtract(const Duration(days: 365));
    final picked = await showAppFormSheet<({DateTime from, DateTime to})>(
      context: context,
      builder: (_) => _TrendRangeSheet(
        initialFrom: initialStart,
        initialTo: initialEnd,
        firstDate: DateTime(now.year - 10),
        lastDate: now,
      ),
    );
    if (picked == null) return;
    ref.read(dashboardCustomRangeProvider.notifier).state = (
      from: picked.from,
      to: picked.to,
    );
    ref.read(dashboardSelectedRangeProvider.notifier).state =
        DashboardRangePreset.custom;
  }

  String _rangeLabel(AppLocalizations l10n, DashboardRangePreset preset) {
    switch (preset) {
      case DashboardRangePreset.m1:
        return l10n.dashboardRange1M;
      case DashboardRangePreset.m3:
        return l10n.dashboardRange3M;
      case DashboardRangePreset.m6:
        return l10n.dashboardRange6M;
      case DashboardRangePreset.y1:
        return l10n.dashboardRange1Y;
      case DashboardRangePreset.y3:
        return l10n.dashboardRange3Y;
      case DashboardRangePreset.all:
        return l10n.dashboardRangeAll;
      case DashboardRangePreset.custom:
        return l10n.dashboardRangeCustom;
    }
  }
}

class _TrendRangeSheet extends StatefulWidget {
  const _TrendRangeSheet({
    required this.initialFrom,
    required this.initialTo,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialFrom;
  final DateTime initialTo;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_TrendRangeSheet> createState() => _TrendRangeSheetState();
}

class _TrendRangeSheetState extends State<_TrendRangeSheet> {
  late final FDateSelectionController<(DateTime, DateTime)?> _controller;

  @override
  void initState() {
    super.initState();
    _controller = FDateSelectionController.range(
      initial: (_utcDay(widget.initialFrom), _utcDay(widget.initialTo)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    return ValueListenableBuilder<(DateTime, DateTime)?>(
      valueListenable: _controller,
      builder: (context, selected, _) {
        return AppSheet(
          title: l10n.dashboardRangeCustom,
          subtitle: selected == null
              ? null
              : '${formatter.date(selected.$1)} - ${formatter.date(selected.$2)}',
          footer: Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.commonCancel),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: FButton(
                  onPress: selected == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop((from: selected.$1, to: selected.$2)),
                  child: Text(l10n.commonConfirm),
                ),
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: colors.foreground.withValues(alpha: AppOpacity.whisper),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s8),
              child: Center(
                child: FCalendar.grid(
                  selectionControl: FDateSelectionControl.managedRange(
                    controller: _controller,
                  ),
                  control: FGridCalendarControl(
                    selectable: (date) {
                      final day = _utcDay(date);
                      return !day.isBefore(_utcDay(widget.firstDate)) &&
                          !day.isAfter(_utcDay(widget.lastDate));
                    },
                    start: _utcDay(widget.firstDate),
                    end: _utcDay(widget.lastDate.add(const Duration(days: 1))),
                    today: _utcDay(DateTime.now()),
                    initial: _utcDay(widget.initialTo),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

DateTime _utcDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
