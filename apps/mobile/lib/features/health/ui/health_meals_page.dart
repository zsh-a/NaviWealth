import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/health_meal_providers.dart';
import '../data/health_series_providers.dart';
import '../domain/health_meal.dart';
import 'health_meal_summary.dart';
import 'meal_date_control.dart';

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
          MealDateControl(
            day: _day,
            today: today,
            browse: true,
            onChanged: (day) => setState(() => _day = day),
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
                    _MealHistoryRow(meal: meal),
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

class _MealHistoryRow extends ConsumerWidget {
  const _MealHistoryRow({required this.meal});
  final HealthMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final image = ref
        .watch(
          healthMealPhotoProvider((
            id: meal.id,
            revision: meal.sync.hlc.toString(),
          )),
        )
        .asData
        ?.value;
    final type = healthMealTypeLabel(l, meal.type);
    final time = context.formatters(ref).time(meal.capturedAt.toLocal());
    final fallback = AppIconTile(
      icon: FLucideIcons.utensils,
      size: AppSpacing.s64,
      iconSize: AppIconSizes.md,
      radius: AppRadius.md,
      color: context.theme.colors.mutedForeground,
      backgroundOpacity: AppOpacity.whisper,
    );
    return AppTappable(
      semanticsLabel: '${l.healthMealEdit}: $type · $time',
      onPress: () => context.push(HealthRoutes.mealEdit(meal.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: image == null
                  ? fallback
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(
                        image,
                        width: AppSpacing.s64,
                        height: AppSpacing.s64,
                        cacheWidth: 192,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.s8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(type, style: context.rowTitleStyle),
                      Text(time, style: context.microCaptionStyle),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    meal.foods.map((food) => food.name).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.captionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    l.healthMealKcal(meal.total.kcal.round().toString()),
                    style: context.labelStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.pencil,
              size: AppIconSizes.sm,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
