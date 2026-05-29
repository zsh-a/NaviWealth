import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';

/// HealthOS contributions to the shared Cmd-K command palette.
///
/// Mirrors `financeCommandPaletteEntries` so HealthOS is reachable from
/// the palette like every other domain (it used to be a dead zone —
/// only Finance was wired). HealthOS is read-only today, so these are
/// pure navigation entries; create / action entries land here when the
/// domain grows write surfaces.
///
/// Labels stay literal (matching the domain shell, which has not been
/// localised yet — D-2.2 follow-up); keywords carry the route path plus
/// English aliases so search works regardless of locale.
List<CommandPaletteEntry> healthCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.health.today',
      label: '健康 · 今日',
      icon: Icons.favorite_outline,
      keywords: const <String>[
        AppRoutes.healthToday,
        'health',
        'today',
        'briefing',
        '健康',
        '今日',
        '简报',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.healthToday),
    ),
    CommandPaletteEntry(
      id: 'nav.health.trend',
      label: '健康 · 趋势',
      icon: Icons.show_chart_outlined,
      keywords: const <String>[
        AppRoutes.healthTrend,
        'health',
        'trend',
        'hrv',
        'sleep',
        '健康',
        '趋势',
        '睡眠',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.healthTrend),
    ),
    CommandPaletteEntry(
      id: 'nav.health.plan',
      label: '健康 · 计划',
      icon: Icons.bolt_outlined,
      keywords: const <String>[
        AppRoutes.healthPlan,
        'health',
        'plan',
        'recovery',
        '健康',
        '计划',
        '恢复',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.healthPlan),
    ),
  ];
}
