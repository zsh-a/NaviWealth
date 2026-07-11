import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

void main() {
  runResponsiveGolden(
    'compact action sheet keeps one crisp surface',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) async {
      await pumpAndSnapshotResponsive(
        tester,
        name: 'action_sheet_compact',
        profile: profile,
        child: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: _BackgroundContent()),
              Align(
                alignment: Alignment.bottomCenter,
                child: AppSheet(
                  title: 'More actions',
                  child: AppActionSheetList(
                    children: [
                      AppActionSheetTile(
                        icon: FLucideIcons.inbox,
                        title: 'Review imports',
                        onPress: () {},
                      ),
                      AppActionSheetTile(
                        icon: FLucideIcons.search,
                        title: 'Search',
                        onPress: () {},
                      ),
                      AppActionSheetTile(
                        icon: FLucideIcons.settings,
                        title: 'Settings',
                        onPress: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _BackgroundContent extends StatelessWidget {
  const _BackgroundContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Activity', style: context.titleLabelStyle),
          const SizedBox(height: AppSpacing.s24),
          for (var index = 0; index < 4; index++) ...[
            const SkeletonBox(height: 64, radius: AppRadius.lg),
            const SizedBox(height: AppSpacing.s12),
          ],
        ],
      ),
    );
  }
}
