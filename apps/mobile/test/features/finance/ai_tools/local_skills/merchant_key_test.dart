import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';

void main() {
  group('merchantKey', () {
    test('strips trailing transaction codes', () {
      expect(merchantKey('STARBUCKS 04291'), 'starbucks');
      expect(merchantKey('AMAZON.COM*XB12K'), 'amazon');
    });

    test('lowercases', () {
      expect(merchantKey('Netflix'), 'netflix');
      expect(merchantKey('NETFLIX.COM'), 'netflix');
    });

    test('keeps Chinese merchant name as a contiguous run', () {
      expect(merchantKey('星巴克咖啡北京店'), '星巴克咖啡北京店');
      expect(merchantKey('美团外卖 -2024-04-01'), '美团外卖');
    });

    test('returns empty string when description has no letters', () {
      expect(merchantKey(''), '');
      expect(merchantKey('1234567'), '');
      expect(merchantKey('---'), '');
    });

    test('takes the first run only', () {
      expect(merchantKey('UBER * EATS'), 'uber');
    });
  });
}
