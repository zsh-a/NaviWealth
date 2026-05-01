import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../shortcuts/shortcut_help_dialog.dart';
import 'command_palette_entry.dart';

/// Build the default command palette entries.
///
/// Pulls labels from [l10n] so search works in the user's language. Keywords
/// include the underlying route path so power users can match by URL.
List<CommandPaletteEntry> defaultCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.home',
      label: l10n.commandPaletteGoOverview,
      icon: Icons.dashboard_outlined,
      keywords: const <String>['/', 'overview', 'home', '总览'],
      run: (BuildContext ctx) => ctx.go('/'),
    ),
    CommandPaletteEntry(
      id: 'nav.assets',
      label: l10n.commandPaletteGoAssets,
      icon: Icons.account_balance_wallet_outlined,
      keywords: const <String>['/assets', 'assets', '资产'],
      run: (BuildContext ctx) => ctx.go('/assets'),
    ),
    CommandPaletteEntry(
      id: 'nav.expenses',
      label: l10n.commandPaletteGoExpenses,
      icon: Icons.receipt_long_outlined,
      keywords: const <String>['/expenses', 'expenses', '支出'],
      run: (BuildContext ctx) => ctx.go('/expenses'),
    ),
    CommandPaletteEntry(
      id: 'nav.analytics',
      label: l10n.commandPaletteGoAnalytics,
      icon: Icons.pie_chart_outline,
      keywords: const <String>['/analytics', 'analytics', '分析'],
      run: (BuildContext ctx) => ctx.go('/analytics'),
    ),
    CommandPaletteEntry(
      id: 'nav.fire',
      label: l10n.commandPaletteGoFire,
      icon: Icons.flag_outlined,
      keywords: const <String>['/fire', 'fire'],
      run: (BuildContext ctx) => ctx.go('/fire'),
    ),
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: Icons.settings_outlined,
      keywords: const <String>['/settings', 'settings', '设置'],
      run: (BuildContext ctx) => ctx.go('/settings'),
    ),
    CommandPaletteEntry(
      id: 'action.newTrade',
      label: l10n.commandPaletteNewTrade,
      icon: Icons.add_chart_outlined,
      keywords: const <String>['/assets/trade', 'trade', 'buy', 'sell', '交易'],
      run: (BuildContext ctx) => ctx.push('/assets/trade'),
    ),
    CommandPaletteEntry(
      id: 'action.newExpense',
      label: l10n.commandPaletteNewExpense,
      icon: Icons.add_card_outlined,
      keywords: const <String>['/expenses/new', 'expense', 'spend', '支出', '记一笔'],
      run: (BuildContext ctx) => ctx.push('/expenses/new'),
    ),
    CommandPaletteEntry(
      id: 'action.openAi',
      label: l10n.commandPaletteOpenAi,
      icon: Icons.smart_toy_outlined,
      keywords: const <String>['/ai', 'ai', 'assistant', '助手'],
      run: (BuildContext ctx) => ctx.push('/ai'),
    ),
    CommandPaletteEntry(
      id: 'action.shortcutHelp',
      label: l10n.commandPaletteShortcutHelp,
      icon: Icons.keyboard_outlined,
      keywords: const <String>['shortcuts', 'help', '快捷键'],
      run: showShortcutHelpDialog,
    ),
  ];
}
