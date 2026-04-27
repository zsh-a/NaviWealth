import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('总览')),
      body: ListView(
        padding: Spacing.pageMobile,
        children: const [
          _NetWorthCard(),
          SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: '今日收益',
            subtitle: '尚未接入实时行情。FIR-4 完成后此处显示当日净值变动。',
            icon: Icons.trending_up,
          ),
          SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: '资产分布',
            subtitle: '将在 FIR-7 完成后显示大类饼图与行业/地域分布。',
            icon: Icons.donut_large,
          ),
          SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: 'FIRE 进度',
            subtitle: 'FIR-9 完成后显示距离财务自由的天数与里程碑。',
            icon: Icons.flag_outlined,
          ),
        ],
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('净资产 (Net Worth)', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s8),
            // Net worth is unknown until accounts are linked — pass null and
            // let MoneyText render the placeholder with the right symbol.
            const MoneyText(
              amount: null,
              currencyCode: 'CNY',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              '基础货币 CNY · 等数据接入后展示',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: Spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Spacing.s4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
