import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/transaction_descriptor_match.dart';

void main() {
  group('compareTransactionDescriptions', () {
    test('exact normalized descriptions are strong', () {
      expect(
        compareTransactionDescriptions('STARBUCKS 04291', 'Starbucks 04291'),
        TransactionDescriptorMatch.strong,
      );
    });

    test('shared merchant with enough descriptor overlap is strong', () {
      expect(
        compareTransactionDescriptions('瑞幸咖啡 · 拿铁', '瑞幸咖啡'),
        TransactionDescriptorMatch.strong,
      );
      expect(
        compareTransactionDescriptions('AMAZON.COM*XB12K', 'Amazon.com*Y9'),
        TransactionDescriptorMatch.strong,
      );
    });

    test('same first word with different merchant line is weak', () {
      expect(
        compareTransactionDescriptions('Apple Store', 'Apple Music'),
        TransactionDescriptorMatch.weakMerchant,
      );
    });

    test('generic or blank descriptions do not match', () {
      expect(
        compareTransactionDescriptions('未命名交易', '未命名交易'),
        TransactionDescriptorMatch.none,
      );
      expect(
        compareTransactionDescriptions('', ''),
        TransactionDescriptorMatch.none,
      );
    });
  });
}
