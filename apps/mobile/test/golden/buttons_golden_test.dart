import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

void main() {
  for (final visual in AppVisualStyle.values) {
    for (final theme in [GoldenTheme.light, GoldenTheme.dark]) {
      testVisualGolden('button hierarchy — ${visual.name}/${theme.name}', (
        tester,
      ) async {
        await pumpAndSnapshotMobile(
          tester,
          name: 'buttons_${visual.name}',
          variant: theme,
          visualStyle: visual,
          child: const _ButtonExamples(),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _ButtonExamples extends StatelessWidget {
  const _ButtonExamples();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s16,
          children: [
            Text('账户操作', style: context.appTheme.type.title),
            AppActionButton(
              prefix: const Icon(FLucideIcons.plus),
              onPress: () {},
              child: const Text('添加记录'),
            ),
            Row(
              spacing: AppSpacing.s12,
              children: [
                Expanded(
                  child: AppActionButton(
                    variant: FButtonVariant.secondary,
                    onPress: () {},
                    child: const Text('调整余额'),
                  ),
                ),
                Expanded(
                  child: AppActionButton(
                    variant: FButtonVariant.outline,
                    onPress: () {},
                    child: const Text('账户详情'),
                  ),
                ),
              ],
            ),
            AppBusyButton(label: '保存记录', busyLabel: '正在保存记录', onPress: () {}),
            AppBusyButton(
              label: '保存记录',
              busyLabel: '正在保存记录',
              busy: true,
              onPress: () {},
            ),
            const AppBusyButton(label: '保存记录', onPress: null),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppQuietButton(label: '查看全部', onPress: () {}),
                AppQuietButton(label: '取消', onPress: () {}),
                AppQuietButton(
                  label: '删除',
                  tone: AppQuietButtonTone.danger,
                  onPress: () {},
                ),
              ],
            ),
            Row(
              spacing: AppSpacing.s12,
              children: [
                AppIconButton(
                  icon: FLucideIcons.search,
                  tooltip: '搜索',
                  onPress: () {},
                ),
                AppIconButton.softPrimary(
                  icon: FLucideIcons.check,
                  tooltip: '确认',
                  onPress: () {},
                ),
                AppIconButton.softPrimaryTile(
                  icon: FLucideIcons.pencil,
                  tooltip: '编辑',
                  onPress: () {},
                ),
                const AppIconButton(
                  icon: FLucideIcons.moreHorizontal,
                  tooltip: '更多',
                  onPress: null,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
