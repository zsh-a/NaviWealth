import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

void main() {
  runAllVariants('app_soft_glass_states', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'app_soft_glass_states',
      variant: variant,
      child: const Scaffold(body: _GlassStateShowcase()),
    );
    expect(tester.takeException(), isNull);
  });
  runAllVariants('app_glass_surface', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'app_glass_surface',
      variant: variant,
      child: const Scaffold(body: _GlassShowcase()),
    );
  });
  runAllVariants('app_soft_glass_surface', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'app_soft_glass_surface',
      variant: variant,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: false),
          child: const Scaffold(body: _GlassShowcase(softLight: true)),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Wealth')),
    );
    await gesture.moveBy(const Offset(44, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    await expectGoldenSurface(
      'goldens/app_soft_glass_pressed_${variant.filenameSuffix}.png',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}

class _GlassStateShowcase extends StatelessWidget {
  const _GlassStateShowcase();

  @override
  Widget build(BuildContext context) {
    final controls = <(String, Set<FTappableVariant>)>[
      ('Rest', {}),
      ('Hover', {FTappableVariant.hovered}),
      ('Selected', {FTappableVariant.selected}),
      ('Focus', {FTappableVariant.focused}),
      ('Pressed', {FTappableVariant.pressed}),
      ('Disabled', {FTappableVariant.disabled}),
    ];
    const statuses = [
      (AppGlassStatus.idle, FLucideIcons.save, 'Ready to save'),
      (AppGlassStatus.busy, FLucideIcons.loaderCircle, 'Saving…'),
      (AppGlassStatus.error, FLucideIcons.circleAlert, 'Save failed · Retry'),
      (AppGlassStatus.disabled, FLucideIcons.lock, 'Unavailable'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Soft light · States', style: context.titleLabelStyle),
            const SizedBox(height: AppSpacing.s16),
            for (var row = 0; row < 3; row++) ...[
              Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(
                      child: AppGlassFeedback(
                        variants: controls[row * 2 + col].$2,
                        child: SizedBox(
                          height: 56,
                          child: Center(
                            child: Text(controls[row * 2 + col].$1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            const SizedBox(height: AppSpacing.s16),
            for (final (status, icon, label) in statuses) ...[
              AppGlassSurface(
                softLight: true,
                frosted: false,
                status: status,
                borderRadius: BorderRadius.circular(AppRadius.md),
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Row(
                  children: [
                    Icon(icon, size: AppIconSizes.sm),
                    const SizedBox(width: AppSpacing.s12),
                    Text(label),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
            ],
            const Spacer(),
            FloatingGlassNavBar(
              items: const [
                FloatingNavTab(
                  icon: FLucideIcons.house,
                  selectedIcon: FLucideIcons.house,
                  label: 'Today',
                ),
                FloatingNavTab(
                  icon: FLucideIcons.wallet,
                  selectedIcon: FLucideIcons.wallet,
                  label: 'Wealth',
                ),
                FloatingNavTab(
                  icon: FLucideIcons.chartPie,
                  selectedIcon: FLucideIcons.chartPie,
                  label: 'Plan',
                ),
              ],
              selectedIndex: 1,
              onIndexChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassShowcase extends StatelessWidget {
  const _GlassShowcase({this.softLight = false});

  final bool softLight;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final surfaces = context.appTheme.surfaces;

    return ColoredBox(
      color: surfaces.canvas,
      child: Stack(
        children: [
          Positioned(
            left: -48,
            top: 132,
            child: _GlowOrb(
              size: 220,
              color: colors.primary.withValues(alpha: AppOpacity.medium),
            ),
          ),
          Positioned(
            right: -56,
            bottom: 60,
            child: _GlowOrb(
              size: 196,
              color: colors.secondary.withValues(alpha: AppOpacity.medium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.s40),
                Text('Your day', style: context.titleLabelStyle),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  'A calm overview across your active domains.',
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
                const Spacer(),
                AppGlassSurface(
                  softLight: softLight,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadow.nav,
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          FLucideIcons.sparkles,
                          color: colors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ready for review',
                              style: context.theme.typography.body.sm.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              '3 meaningful updates',
                              style: context.theme.typography.body.xs.copyWith(
                                color: colors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        FLucideIcons.chevronRight,
                        color: colors.mutedForeground,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                AppGlassSurface(
                  softLight: softLight,
                  frosted: !softLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  boxShadow: AppShadow.nav,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s20,
                    vertical: AppSpacing.s12,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _NavItem(
                        icon: FLucideIcons.house,
                        label: 'Today',
                        selected: true,
                      ),
                      _NavItem(icon: FLucideIcons.wallet, label: 'Wealth'),
                      _NavItem(icon: FLucideIcons.brain, label: 'Knowledge'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = selected ? colors.primary : colors.mutedForeground;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: SizedBox(
        width: 72,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 19),
            const SizedBox(height: AppSpacing.s4),
            Text(
              label,
              style: context.theme.typography.body.xs.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
