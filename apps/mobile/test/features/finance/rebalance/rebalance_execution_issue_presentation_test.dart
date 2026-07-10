import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_execution_issue_presentation.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';
import 'package:naviwealth/l10n/gen/app_localizations_zh.dart';

void main() {
  test('every issue code resolves to safe English and Chinese copy', () {
    const sentinel = 'RAW_DEBUG_SENTINEL';
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    for (final code in RebalanceExecutionIssueCode.values) {
      final issue = RebalanceExecutionIssue(code, sentinel);
      for (final copy in [issue.userMessage(en), issue.userMessage(zh)]) {
        expect(copy.trim(), isNotEmpty, reason: code.name);
        expect(copy, isNot(contains(sentinel)), reason: code.name);
      }
    }
  });
}
