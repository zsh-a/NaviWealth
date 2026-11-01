import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/chat_composer.dart';
import 'package:naviwealth/features/ai_chat/ui/decision_card.dart';
import 'package:naviwealth/features/ai_chat/ui/decision_request.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/tool_invocation_card.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_category_picker.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  for (final visual in AppVisualStyle.values) {
    for (final variant in [GoldenTheme.light, GoldenTheme.dark]) {
      for (final highContrast in [false, true]) {
        if (highContrast && visual == AppVisualStyle.classic) continue;
        final suffix = '${visual.name}${highContrast ? '_contrast' : ''}';
        testVisualGolden('choice surfaces — $suffix/${variant.name}', (
          tester,
        ) async {
          await pumpAndSnapshotMobile(
            tester,
            name: 'choice_surfaces_$suffix',
            variant: variant,
            visualStyle: visual,
            highContrast: highContrast,
            locale: const Locale('zh'),
            child: const _ChoiceExamples(),
          );
          expect(tester.takeException(), isNull);
        });
        testVisualGolden('AI surfaces — $suffix/${variant.name}', (
          tester,
        ) async {
          await pumpAndSnapshotMobile(
            tester,
            name: 'ai_choice_surfaces_$suffix',
            variant: variant,
            visualStyle: visual,
            highContrast: highContrast,
            locale: const Locale('zh'),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
            ],
            child: const _AiExamples(),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

class _ChoiceExamples extends StatelessWidget {
  const _ChoiceExamples();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s16,
          children: [
            Text('账户类型', style: context.appTheme.type.title),
            AccountCategoryPicker(
              value: AccountCategory.bank,
              onChanged: (_) {},
            ),
            Text('展示维度', style: context.appTheme.type.title),
            AppAdaptiveChoice<String>.inline(
              title: '展示维度',
              options: const ['按类别', '按币种'],
              value: '按类别',
              labelOf: (value) => value,
              onChanged: (_) {},
            ),
            Text('内容表面', style: context.appTheme.type.title),
            const SoftCard(
              padding: EdgeInsets.all(AppSpacing.s20),
              child: SizedBox(height: 80, child: Text('已加载')),
            ),
            const SkeletonCard(
              child: SizedBox(height: 80, child: SkeletonBox(height: 24)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AiExamples extends StatelessWidget {
  const _AiExamples();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s16,
          children: [
            const AiMarkdown(text: '**记录摘要**\n\n检查已有记录，再选择下一步。'),
            const ToolInvocationCard(
              invocation: ToolInvocation(
                id: 'golden-tool',
                name: 'get_holdings',
                input: {},
                output: {'holdings': <Object?>[]},
              ),
            ),
            DecisionCard(
              request: const DecisionRequest(
                title: '选择下一步',
                context: '请选择本次记录的处理方式。',
                allowCustom: false,
                options: [
                  DecisionOption(
                    id: 'review',
                    label: '检查记录',
                    description: '核对已录入的数据',
                    recommended: true,
                  ),
                  DecisionOption(
                    id: 'later',
                    label: '稍后处理',
                    description: '保留当前记录',
                  ),
                ],
              ),
              interactive: true,
              selectedOptionId: 'review',
              onSelect: (_, _) {},
            ),
            ChatComposer(
              isStreaming: false,
              initialText: '查看本月记录',
              onSend: (_) {},
              onCancel: () {},
            ),
          ],
        ),
      ),
    ),
  );
}
