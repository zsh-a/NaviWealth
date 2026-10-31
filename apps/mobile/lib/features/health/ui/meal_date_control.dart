import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_calendar_providers.dart';
import '../data/health_series.dart' show healthDay;

/// Date-only presentation: the stored meal day must never shift with timezone.
({String title, String detail, String full}) mealDateLabels({
  required AppLocalizations l10n,
  required Locale locale,
  required DateTime day,
  required DateTime today,
}) {
  final selected = healthDay(day);
  final current = healthDay(today);
  final language = locale.toLanguageTag();
  final date = selected.year == current.year
      ? DateFormat.MMMd(language).format(selected)
      : DateFormat.yMMMd(language).format(selected);
  final weekday = DateFormat.E(language).format(selected);
  final relative = selected == current
      ? l10n.healthMealDateToday
      : selected == current.subtract(const Duration(days: 1))
      ? l10n.healthMealDateYesterday
      : null;
  return (
    title: relative ?? date,
    detail: relative == null ? weekday : '$date · $weekday',
    full: DateFormat.yMMMMEEEEd(language).format(selected),
  );
}

/// Meal context in a form, or day navigation above the daily meal history.
class MealDateControl extends StatelessWidget {
  const MealDateControl({
    super.key,
    required this.day,
    required this.today,
    required this.onChanged,
    this.browse = false,
  });

  final DateTime day;
  final DateTime today;
  final ValueChanged<DateTime>? onChanged;
  final bool browse;

  Future<void> _choose(BuildContext context) async {
    if (onChanged == null) return;
    final selected = await showAppFormSheet<DateTime>(
      context: context,
      builder: (_) => _MealDatePicker(day: healthDay(day)),
    );
    if (context.mounted && selected != null && selected != healthDay(day)) {
      onChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = healthDay(today);
    final selected = healthDay(day);
    final labels = mealDateLabels(
      l10n: l,
      locale: Localizations.localeOf(context),
      day: selected,
      today: current,
    );
    final enabled = onChanged != null;
    final dateButton = AppActionTappable(
      key: const Key('meal-date-open'),
      semanticsLabel: l.healthMealDateSelectLabel(labels.full),
      onPress: enabled
          ? AppInteraction.wrap(
              () => _choose(context),
              intent: AppInteractionIntent.select,
            )
          : null,
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      builder: (context, variants, child) {
        final alpha = variants.contains(FTappableVariant.pressed)
            ? AppOpacity.faint
            : variants.contains(FTappableVariant.hovered)
            ? AppOpacity.whisper
            : AppOpacity.transparent;
        return AnimatedContainer(
          duration: AppMotionPolicy.duration(
            context,
            Motion.fast,
            role: AppMotionRole.decorative,
          ),
          curve: Motion.standardDecelerate,
          decoration: BoxDecoration(
            color: context.theme.colors.foreground.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: child,
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppControlHeights.touchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              if (!browse) ...[
                Icon(
                  FLucideIcons.calendarDays,
                  size: AppIconSizes.h18,
                  color: context.theme.colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
              ],
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  alignment: browse
                      ? WrapAlignment.center
                      : WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(labels.title, style: context.rowTitleStyle),
                    Text(labels.detail, style: context.captionStyle),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Icon(
                FLucideIcons.chevronDown,
                size: AppIconSizes.xs,
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
    if (!browse) return dateButton;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconButton(
              key: const Key('meal-date-previous'),
              icon: FLucideIcons.chevronLeft,
              tooltip: l.healthMealDatePrevious,
              onPress: enabled && selected.isAfter(DateTime.utc(1970))
                  ? () => onChanged!(selected.subtract(const Duration(days: 1)))
                  : null,
            ),
            Expanded(child: dateButton),
            AppIconButton(
              key: const Key('meal-date-next'),
              icon: FLucideIcons.chevronRight,
              tooltip: l.healthMealDateNext,
              onPress: enabled && selected.isBefore(current)
                  ? () => onChanged!(selected.add(const Duration(days: 1)))
                  : null,
            ),
          ],
        ),
        if (selected != current)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppQuietButton(
              key: const Key('meal-date-return-today'),
              label: l.healthMealDateReturnToday,
              onPress: enabled ? () => onChanged!(current) : null,
            ),
          ),
      ],
    );
  }
}

class _MealDatePicker extends ConsumerWidget {
  const _MealDatePicker({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final today = ref.watch(healthCalendarDayProvider);
    final first = DateTime.utc(1970);
    final selected = day.isAfter(today)
        ? today
        : day.isBefore(first)
        ? first
        : day;
    void choose(DateTime value) {
      final date = healthDay(value);
      if (!date.isBefore(first) && !date.isAfter(today)) {
        Navigator.of(context).pop(date);
      }
    }

    return AppSheet(
      title: l.healthMealDateChoose,
      footer: AppQuietButton(
        label: l.commonCancel,
        expanded: true,
        onPress: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppActionButton(
                buttonKey: const Key('meal-date-today'),
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.md,
                mainAxisSize: MainAxisSize.min,
                hapticIntent: AppInteractionIntent.select,
                onPress: () => choose(today),
                child: Text(l.healthMealDateToday),
              ),
              AppActionButton(
                buttonKey: const Key('meal-date-yesterday'),
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.md,
                mainAxisSize: MainAxisSize.min,
                hapticIntent: AppInteractionIntent.select,
                onPress: today.isAfter(first)
                    ? () => choose(today.subtract(const Duration(days: 1)))
                    : null,
                child: Text(l.healthMealDateYesterday),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          LayoutBuilder(
            builder: (context, constraints) {
              final style = context.theme.calendarStyle;
              final direction = Directionality.of(context);
              final inset =
                  style.padding.resolve(direction).horizontal +
                  style.decoration.padding.resolve(direction).horizontal;
              final size = style.dayPickerStyle.daySize;
              final width = ((constraints.maxWidth - inset) / 7).clamp(
                0.0,
                size.width,
              );
              final text = style.dayPickerStyle.dayStyles.resolve({}).textStyle;
              final textHeight =
                  MediaQuery.textScalerOf(context).scale(text.fontSize!) *
                      (text.height ?? 1.4) +
                  AppSpacing.s8;
              final height = textHeight < size.height
                  ? size.height
                  : textHeight.ceilToDouble();
              return Center(
                child: FCalendar.wheel(
                  style: FCalendarStyleDelta.delta(
                    dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
                      daySize: Size(width, height),
                    ),
                  ),
                  dayBuilder: (context, styles, localizations, date, variants) {
                    final dayStyle = styles.resolve(variants);
                    return DecoratedBox(
                      key: ValueKey(
                        'meal-date-cell-${date.year}-${date.month}-${date.day}',
                      ),
                      decoration: dayStyle.background,
                      child: DecoratedBox(
                        decoration: dayStyle.foreground,
                        child: Center(
                          child: Text(
                            NumberFormat.decimalPattern(
                              localizations.localeName,
                            ).format(date.day),
                            style: dayStyle.textStyle,
                          ),
                        ),
                      ),
                    );
                  },
                  key: ValueKey(today),
                  fixedWeeks: true,
                  headerBuilder: (context, controller, _, _) =>
                      _MealCalendarHeader(controller: controller),
                  control: FWheelCalendarControl(
                    initial: selected,
                    today: today,
                    start: first,
                    end: today,
                    selectable: (value) =>
                        !healthDay(value).isBefore(first) &&
                        !healthDay(value).isAfter(today),
                  ),
                  selectionControl: FDateSelectionControl.managedSingle(
                    initial: selected,
                  ),
                  onDayPress: choose,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Keep the calendar's controls reachable without shrinking Dynamic Type.
class _MealCalendarHeader extends StatelessWidget {
  const _MealCalendarHeader({required this.controller});
  final FWheelCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final l = FLocalizations.of(context) ?? FDefaultLocalizations();
    final language = Localizations.localeOf(context).toLanguageTag();
    final label = DateFormat.yMMMM(language).format(controller.currentMonth);
    final hint = controller.monthYear
        ? l.calendarShowDaysSemanticsHint
        : l.calendarShowMonthYearPickerSemanticsHint;
    final title = AppActionTappable(
      key: const Key('meal-calendar-period'),
      semanticsLabel: '$label · $hint',
      onPress: controller.toggleMonthYearPicker,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppControlHeights.touchTarget,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.rowTitleStyle)),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.chevronDown,
              size: AppIconSizes.xs,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
    if (controller.monthYear) return title;
    final navigation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: FLucideIcons.chevronLeft,
          tooltip: l.calendarPreviousMonthSemanticsLabel,
          onPress: controller.day.hasPrevious
              ? () => controller.day.previous()
              : null,
        ),
        AppIconButton(
          icon: FLucideIcons.chevronRight,
          tooltip: l.calendarNextMonthSemanticsLabel,
          onPress: controller.day.hasNext ? () => controller.day.next() : null,
        ),
      ],
    );
    if (MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Align(alignment: AlignmentDirectional.centerEnd, child: navigation),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        navigation,
      ],
    );
  }
}
