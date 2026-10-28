import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/health_meal_providers.dart';
import '../data/health_series_providers.dart';
import '../domain/health_meal.dart';
import 'health_meal_summary.dart';

class HealthMealsPage extends ConsumerStatefulWidget {
  const HealthMealsPage({super.key});
  @override
  ConsumerState<HealthMealsPage> createState() => _HealthMealsPageState();
}

class _HealthMealsPageState extends ConsumerState<HealthMealsPage> {
  late DateTime _day;
  @override
  void initState() {
    super.initState();
    _day = ref.read(healthCalendarDayProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = ref.watch(healthCalendarDayProvider);
    final meals = ref.watch(healthMealsProvider(_day));
    return FScaffold(
      header: appSubPageHeader(
        context: context,
        title: Text(l.healthMealsTitle),
      ),
      child: ListView(
        children: [
          FDateField.calendar(
            key: ValueKey(_day),
            label: Text(l.commonDate),
            clearable: false,
            selectionControl: FDateSelectionControl.managedSingle(
              initial: _day,
              onChange: (day) {
                if (day != null) {
                  setState(
                    () => _day = DateTime.utc(day.year, day.month, day.day),
                  );
                }
              },
            ),
            calendar: FDateFieldGridCalendarProperties(
              control: FGridCalendarControl(
                start: DateTime.utc(1970),
                end: today.add(const Duration(days: 1)),
                today: today,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppBusyButton(
            label: l.healthMealRecord,
            onPress: () => context.push(
              '${HealthRoutes.mealNew}?day=${_day.toIso8601String().substring(0, 10)}',
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          Text(l.healthMealRecorded, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          meals.whenOrLoading(
            context: context,
            loading: () => const SkeletonBox(height: 100),
            onRetry: () => ref.invalidate(healthMealsProvider(_day)),
            data: (entries) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entries.isEmpty)
                  Text(l.healthMealEmpty, style: context.captionStyle)
                else ...[
                  HealthMealTotals(
                    total: entries.fold(
                      MealNutrients.zero,
                      (sum, meal) => sum + meal.total,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  for (final meal in entries) ...[
                    AppTappable(
                      onPress: () =>
                          context.push(HealthRoutes.mealEdit(meal.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    healthMealTypeLabel(l, meal.type),
                                    style: context.rowTitleStyle,
                                  ),
                                ),
                                Text(
                                  l.healthMealKcal(
                                    meal.total.kcal.round().toString(),
                                  ),
                                  style: context.labelStyle,
                                ),
                                const SizedBox(width: AppSpacing.s8),
                                const Icon(
                                  FLucideIcons.pencil,
                                  size: AppIconSizes.sm,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              meal.foods.map((food) => food.name).join(' · '),
                              style: context.captionStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const AppGroupedDivider(),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(l.healthMealEstimateHint, style: context.captionStyle),
        ],
      ),
    );
  }
}
