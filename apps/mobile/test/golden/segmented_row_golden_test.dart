import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '_golden_setup.dart';

void main() {
  for (final visual in AppVisualStyle.values) {
    for (final theme in [GoldenTheme.light, GoldenTheme.dark]) {
      testVisualGolden('form choices — ${visual.name}/${theme.name}', (
        tester,
      ) async {
        await pumpAndSnapshotMobile(
          tester,
          name: 'form_choices_${visual.name}',
          variant: theme,
          visualStyle: visual,
          child: const _ChoiceExamples(),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _ChoiceExamples extends StatelessWidget {
  const _ChoiceExamples();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s16,
          children: [
            Text('交易类型', style: context.appTheme.type.title),
            SegmentedRow<String>(
              options: const ['买入', '卖出'],
              value: '买入',
              labelOf: (value) => value,
              onChanged: (_) {},
            ),
            SegmentedRow<String>(
              options: const ['Buy', 'Sell'],
              value: 'Sell',
              labelOf: (value) => value,
              onChanged: null,
            ),
            Text('账户分类', style: context.appTheme.type.title),
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: SegmentedRow<int>(
                options: const [0, 1, 2, 3],
                value: 2,
                labelOf: (value) => ['银行账户', '现金账户', '证券账户', '其他账户'][value],
                iconOf: (_) => FLucideIcons.wallet,
                onChanged: (_) {},
              ),
            ),
            AppAdaptiveChoice<int>(
              title: '选择账户类型',
              options: const [0, 1, 2, 3],
              value: 2,
              labelOf: (value) => ['银行账户', '现金账户', '证券账户', '其他账户'][value],
              iconOf: (_) => FLucideIcons.wallet,
              onChanged: (_) {},
            ),
            Text('展示维度', style: context.appTheme.type.title),
            SegmentedRow<String>.inline(
              options: const ['按类别', '按币种'],
              value: '按类别',
              labelOf: (value) => value,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}
