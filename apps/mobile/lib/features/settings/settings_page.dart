import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/design_system.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('账户'),
            subtitle: Text('登录与多端同步 (FIR-27 / FIR-28)'),
          ),
          const ListTile(
            leading: Icon(Icons.currency_exchange),
            title: Text('基础货币'),
            subtitle: Text('CNY (默认)'),
          ),
          const Divider(),
          const _SectionHeader(label: '外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Text(_themeModeLabel(themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  tooltip: '跟随系统',
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  tooltip: '浅色',
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  tooltip: '深色',
                ),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('涨跌色'),
            subtitle: Text(_marketModeLabel(marketMode)),
            trailing: PopupMenuButton<MarketColorMode>(
              icon: const Icon(Icons.tune),
              onSelected: (m) =>
                  ref.read(marketColorModeProvider.notifier).set(m),
              itemBuilder: (context) => [
                for (final m in MarketColorMode.values)
                  PopupMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        if (m == marketMode)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(_marketModeLabel(m)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _MarketColorPreview(),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于 NaviWealth'),
            subtitle: Text('v0.1.0'),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  String _marketModeLabel(MarketColorMode mode) => switch (mode) {
    MarketColorMode.redUpGreenDown => '红涨绿跌 (中国)',
    MarketColorMode.greenUpRedDown => '绿涨红跌 (国际)',
    MarketColorMode.colorblind => '色盲友好 (蓝/橙)',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MarketColorPreview extends StatelessWidget {
  const _MarketColorPreview();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: Spacing.s8,
      runSpacing: Spacing.s8,
      children: [
        DeltaChip(value: 1.23, format: DeltaFormat.percent),
        DeltaChip(value: -0.42, format: DeltaFormat.percent),
        DeltaChip(value: 0, format: DeltaFormat.percent),
      ],
    );
  }
}
