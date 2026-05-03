import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../assets/assets_page.dart';
import '../liabilities/ui/liabilities_page.dart';

/// Portfolio tab — umbrella page with a segmented control toggling
/// between Assets and Liabilities views.
class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tab = ref.watch(_portfolioTabProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navPortfolio),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _SegmentedControl(
            current: tab,
            onChanged: (PortfolioTab t) =>
                ref.read(_portfolioTabProvider.notifier).state = t,
          ),
        ),
      ),
      body: tab == PortfolioTab.assets
          ? const AssetsPage(embedded: true)
          : const LiabilitiesPage(embedded: true),
    );
  }
}

enum PortfolioTab { assets, liabilities }

final StateProvider<PortfolioTab> _portfolioTabProvider =
    StateProvider<PortfolioTab>((_) => PortfolioTab.assets);

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.current, required this.onChanged});

  final PortfolioTab current;
  final ValueChanged<PortfolioTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s4,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            _SegmentChip(
              label: l10n.portfolioAssetsTab,
              icon: Icons.account_balance_wallet_outlined,
              selected: current == PortfolioTab.assets,
              onTap: () => onChanged(PortfolioTab.assets),
            ),
            _SegmentChip(
              label: l10n.portfolioLiabilitiesTab,
              icon: Icons.payments_outlined,
              selected: current == PortfolioTab.liabilities,
              onTap: () => onChanged(PortfolioTab.liabilities),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const selectedColor = ColorPalette.brand500;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.emphasizedDecelerate,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.full),
            boxShadow: selected ? AppElevations.of(context).level1 : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? selectedColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? selectedColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
