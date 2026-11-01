import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

Widget _translucent(GoldenTheme variant, Widget child) => AppThemeScope(
  data: resolveAppTheme(
    ThemeInputs(
      brightness: variant.brightness,
      marketMode: variant.marketMode,
      materialStyle: AppMaterialStyle.translucent,
    ),
  ),
  child: child,
);

void main() {
  runAllVariants('app_glass_surface', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'app_glass_surface',
      variant: variant,
      child: _translucent(variant, const Scaffold(body: _GlassShowcase())),
    );
  });
  runAllVariants('app_soft_glass_surface', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'app_soft_glass_surface',
      variant: variant,
      child: _translucent(
        variant,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: false),
            child: const Scaffold(body: _GlassShowcase(softLight: true)),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Ready for review')),
    );
    await gesture.moveBy(const Offset(44, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    // Pressing and dragging leave the same static material, even when the
    // platform permits decorative motion.
    await expectGoldenSurface(
      'goldens/app_soft_glass_surface_${variant.filenameSuffix}.png',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
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
                      icon: FLucideIcons.brain,
                      selectedIcon: FLucideIcons.brain,
                      label: 'Knowledge',
                    ),
                  ],
                  selectedIndex: 0,
                  onIndexChanged: (_) {},
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
