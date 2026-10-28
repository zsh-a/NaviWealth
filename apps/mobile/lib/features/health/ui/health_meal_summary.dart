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

String healthMealTypeLabel(AppLocalizations l, HealthMealType type) =>
    switch (type) {
      HealthMealType.breakfast => l.healthMealBreakfast,
      HealthMealType.lunch => l.healthMealLunch,
      HealthMealType.dinner => l.healthMealDinner,
      HealthMealType.snack => l.healthMealSnack,
    };

class HealthMealTotals extends StatelessWidget {
  const HealthMealTotals({super.key, required this.total});
  final MealNutrients total;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.healthMealKcal(total.kcal.round().toString()),
          style: context.titleLabelStyle,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          l.healthMealMacros(
            total.protein.toStringAsFixed(1),
            total.carbs.toStringAsFixed(1),
            total.fat.toStringAsFixed(1),
          ),
          style: context.captionStyle,
        ),
      ],
    );
  }
}

class HealthMealToday extends ConsumerWidget {
  const HealthMealToday({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final day = ref.watch(healthCalendarDayProvider);
    final data = ref.watch(healthMealsProvider(day));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l.healthMealRecorded, style: context.labelStyle),
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => context.push(HealthRoutes.mealNew),
              child: Flexible(child: Text(l.healthMealRecord)),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => context.push(HealthRoutes.meals),
              child: Flexible(child: Text(l.healthMealHistory)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        data.whenOrLoading(
          context: context,
          loading: () => const SkeletonBox(height: 54),
          onRetry: () => ref.invalidate(healthMealsProvider(day)),
          data: (meals) => meals.isEmpty
              ? Text(l.healthMealEmpty, style: context.captionStyle)
              : HealthMealTotals(
                  total: meals.fold(
                    MealNutrients.zero,
                    (sum, meal) => sum + meal.total,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(l.healthMealEstimateHint, style: context.microCaptionStyle),
      ],
    );
  }
}
