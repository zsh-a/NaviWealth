import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/amount_field.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/percent_field.dart';

import '_golden_setup.dart';

void main() {
  runAllVariants('numeric_fields', (tester, variant) async {
    final controllers = [
      TextEditingController(text: '85.125'),
      TextEditingController(text: '-2.125'),
      TextEditingController(text: '12500.50'),
      TextEditingController(text: '12'),
      TextEditingController(text: 'abc'),
      TextEditingController(text: '5'),
    ];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await pumpAndSnapshotMobile(
      tester,
      name: 'numeric_fields',
      variant: variant,
      locale: const Locale('zh'),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.s24),
              PercentField(
                control: FTextFieldControl.managed(controller: controllers[0]),
                label: const Text('年度残值率'),
                decimalPlaces: null,
              ),
              const SizedBox(height: AppSpacing.s16),
              PercentField(
                control: FTextFieldControl.managed(controller: controllers[1]),
                label: const Text('预期年化收益率'),
                allowNegative: true,
                decimalPlaces: null,
              ),
              const SizedBox(height: AppSpacing.s16),
              AmountField(
                controller: controllers[2],
                label: '资金预算',
                currencyCode: 'CNY',
              ),
              const SizedBox(height: AppSpacing.s16),
              AppNumberField(
                control: FTextFieldControl.managed(controller: controllers[3]),
                label: const Text('持续时间'),
                unit: '个月',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.s16),
              AppNumberField(
                control: FTextFieldControl.managed(controller: controllers[4]),
                label: const Text('一次性支出'),
                unit: 'CNY',
                forceErrorText: '请输入有效金额',
              ),
              const SizedBox(height: AppSpacing.s16),
              PercentField(
                control: FTextFieldControl.managed(controller: controllers[5]),
                label: const Text('允许偏差'),
                enabled: false,
              ),
            ],
          ),
        ),
      ),
    );
  });
}
