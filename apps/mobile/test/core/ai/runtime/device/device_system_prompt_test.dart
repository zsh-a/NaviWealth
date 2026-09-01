import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart';

void main() {
  test('guides analytical answers toward a concise decision structure', () {
    expect(
      kDeviceSystemPromptBase,
      allOf(
        contains('结论 / 依据 / 缺失信息 / 下一步'),
        contains('每个关键数值说明数据来源或截止时间'),
        contains('无法确认时明确说不确定'),
      ),
    );
  });

  test('keeps domain blocks additive to the shared experience contract', () {
    const domainBlock = '[FinanceOS 域]\n只使用已注册的财务工具。';
    final prompt = composeDeviceSystemPrompt(
      domainBlocks: <String>[domainBlock],
    );

    expect(prompt, startsWith(kDeviceSystemPromptBase));
    expect(prompt, endsWith(domainBlock));
  });
}
