import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'health_route_paths.dart';

/// HealthOS contributions to the shared Cmd-K command palette.
///
/// Navigation entries plus metric/search aliases. HealthOS remains
/// mostly read-only, so actions stay in-page; the palette should still
/// help users jump to sleep, HRV, VO2 max, Garmin, and recovery surfaces.
List<CommandPaletteEntry> healthCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.health.today',
      label: l10n.healthCommandToday,
      icon: FLucideIcons.heart,
      keywords: <String>[
        HealthRoutes.today,
        'health',
        'today',
        'sync',
        'garmin',
        l10n.healthTodayTitle,
        '健康',
        '今日',
        '同步',
      ],
      run: (BuildContext ctx) => ctx.go(HealthRoutes.today),
    ),
    CommandPaletteEntry(
      id: 'nav.health.trend',
      label: l10n.healthCommandTrend,
      icon: FLucideIcons.trendingUp,
      keywords: <String>[
        HealthRoutes.trend,
        'health',
        'trend',
        'hrv',
        'sleep',
        'resting heart rate',
        'rhr',
        'vo2',
        'vo2 max',
        'steps',
        'spo2',
        'body battery',
        'training load',
        l10n.healthTrendTitle,
        l10n.healthTrendHrvSubtitle,
        l10n.healthTrendSleepSubtitle,
        l10n.healthTrendRhrTitle,
        l10n.healthTrendVo2MaxTitle,
        l10n.healthTrendStepsSubtitle,
        l10n.healthTrendBodyBatteryTitle,
        l10n.healthTrendTrainingLoadTitle,
        '健康',
        '趋势',
        '睡眠',
        '心率',
        '血氧',
        '步数',
        '训练负荷',
      ],
      run: (BuildContext ctx) => ctx.go(HealthRoutes.trend),
    ),
    CommandPaletteEntry(
      id: 'nav.health.plan',
      label: l10n.healthCommandPlan,
      icon: FLucideIcons.zap,
      keywords: <String>[
        HealthRoutes.plan,
        'health',
        'plan',
        'recovery',
        'readiness',
        'workout',
        'rest',
        'sleep plan',
        l10n.healthPlanTitle,
        l10n.healthPlanTodayActions,
        l10n.healthPlanLightActivity,
        '健康',
        '计划',
        '恢复',
        '训练',
        '休息',
      ],
      // Plan merged into Today hero guidance.
      run: (BuildContext ctx) => ctx.go(HealthRoutes.today),
    ),
  ];
}
