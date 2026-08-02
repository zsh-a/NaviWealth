@Tags(['golden', 'responsive-golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

void main() {
  for (final configuration in _AdaptiveGoldenConfiguration.values) {
    runResponsiveGolden(
      'adaptive layout matrix — ${configuration.name}',
      profile: configuration.baseProfile,
      body: (tester, profile) => pumpAndSnapshotResponsive(
        tester,
        name: 'adaptive_layout_${configuration.name}',
        profile: profile,
        logicalSizeOverride: configuration.logicalSize,
        devicePixelRatioOverride: configuration.devicePixelRatio,
        textScalerOverride: configuration.textScaler,
        targetPlatformOverride: configuration.targetPlatform,
        touchOverride: configuration.touch,
        compactOverride: configuration.compact,
        child: const _AdaptiveLayoutFixture(),
      ),
    );
  }
}

enum _AdaptiveGoldenConfiguration {
  narrow,
  medium,
  expanded,
  wide,
  extraWide,
  textScale,
}

extension on _AdaptiveGoldenConfiguration {
  ResponsiveGoldenProfile get baseProfile => switch (this) {
    _AdaptiveGoldenConfiguration.wide ||
    _AdaptiveGoldenConfiguration.extraWide => ResponsiveGoldenProfile.wide,
    _AdaptiveGoldenConfiguration.textScale => ResponsiveGoldenProfile.textScale,
    _ => ResponsiveGoldenProfile.narrow,
  };

  Size get logicalSize => switch (this) {
    _AdaptiveGoldenConfiguration.narrow ||
    _AdaptiveGoldenConfiguration.textScale => const Size(390, 844),
    _AdaptiveGoldenConfiguration.medium => const Size(700, 900),
    _AdaptiveGoldenConfiguration.expanded => const Size(1000, 900),
    _AdaptiveGoldenConfiguration.wide => const Size(1280, 900),
    _AdaptiveGoldenConfiguration.extraWide => const Size(1600, 1000),
  };

  double get devicePixelRatio => switch (this) {
    _AdaptiveGoldenConfiguration.narrow ||
    _AdaptiveGoldenConfiguration.textScale => 2,
    _ => 1,
  };

  TextScaler get textScaler => switch (this) {
    _AdaptiveGoldenConfiguration.textScale => const TextScaler.linear(2),
    _ => TextScaler.noScaling,
  };

  TargetPlatform get targetPlatform => switch (this) {
    _AdaptiveGoldenConfiguration.wide ||
    _AdaptiveGoldenConfiguration.extraWide => TargetPlatform.linux,
    _ => TargetPlatform.iOS,
  };

  bool get touch => switch (this) {
    _AdaptiveGoldenConfiguration.wide ||
    _AdaptiveGoldenConfiguration.extraWide => false,
    _ => true,
  };

  bool get compact => switch (this) {
    _AdaptiveGoldenConfiguration.wide ||
    _AdaptiveGoldenConfiguration.extraWide => true,
    _ => false,
  };
}

class _AdaptiveLayoutFixture extends StatelessWidget {
  const _AdaptiveLayoutFixture();

  @override
  Widget build(BuildContext context) {
    return AppCanvasScaffold(
      childPad: false,
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.dashboard,
        header: const SoftCard.hero(
          child: SizedBox(
            height: 96,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('Adaptive workspace'),
            ),
          ),
        ),
        primary: AdaptiveSupportingPane(
          primary: Column(
            children: [
              for (var index = 0; index < 3; index++) ...[
                SoftCard.raised(
                  child: SizedBox(
                    height: 72,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text('Primary item ${index + 1}'),
                    ),
                  ),
                ),
                if (index < 2) const SizedBox(height: AppSpacing.s12),
              ],
            ],
          ),
          supporting: const SoftCard.raised(
            child: SizedBox(
              height: 180,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: Text('Supporting context'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
