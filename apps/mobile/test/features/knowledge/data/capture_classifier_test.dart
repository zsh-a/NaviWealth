import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/capture_classifier.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';

void main() {
  const c = HeuristicCaptureClassifier();

  group('HeuristicCaptureClassifier — routine detection', () {
    test(
      '港卡需要定期活跃 (no explicit interval) — routine with default 180d',
      () async {
        final r = await c.classify(text: '港卡需要定期做一次活跃交易，否则会休眠。');
        expect(r.kind, CaptureKind.routine);
        expect(r.intervalDays, 180);
        expect(r.scope, 'finance/cards');
        expect(r.confidence, greaterThan(0.5));
        expect(r.statement, isNotNull);
      },
    );

    test('"每 6 个月做一次" — explicit interval parsed', () async {
      final r = await c.classify(text: '港卡每 6 个月做一次活跃交易');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.confidence, greaterThanOrEqualTo(0.8));
    });

    test('"每 90 天" — pure-day interval', () async {
      final r = await c.classify(text: '每 90 天做一次 portfolio 复盘');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 90);
    });

    test('"每年报税" — year interval', () async {
      final r = await c.classify(text: '每年报税前对一遍账');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 365);
      expect(r.scope, 'finance/tax');
    });

    test('"每周做一次 review" — weekly cadence', () async {
      final r = await c.classify(text: '每周做一次 portfolio review');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 7);
    });

    test('English "every 6 months" recurring marker fires', () async {
      final r = await c.classify(text: 'Activate HK card every 6 months.');
      expect(r.kind, CaptureKind.routine);
      // Marker-only (no Chinese 每 N 单位 regex match) — interval falls
      // back to default 180.
      expect(r.intervalDays, 180);
    });

    test('体检 + scope guess', () async {
      final r = await c.classify(text: '每年做一次体检');
      expect(r.kind, CaptureKind.routine);
      expect(r.scope, 'health');
    });

    test('statement is trimmed and length-capped', () async {
      final long = '港卡需要定期 ' * 30;
      final r = await c.classify(text: long);
      expect(r.kind, CaptureKind.routine);
      expect(r.statement!.length, lessThanOrEqualTo(61));
    });

    test('"每个月定投1000 \$IBIT" — 每个X form + investing scope', () async {
      final r = await c.classify(text: '每个月定投1000 \$IBIT');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 30);
      expect(r.scope, 'finance/investing');
    });

    test('"每个星期 review" — weekly via 每个 prefix', () async {
      final r = await c.classify(text: '每个星期做一次 portfolio review');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 7);
    });

    test('"每个年" rare form still parses', () async {
      final r = await c.classify(text: '每个年做一次大复盘');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 365);
    });
  });

  group('HeuristicCaptureClassifier — structured fallback kinds', () {
    test('decision language upgrades to Decision candidate', () async {
      final r = await c.classify(text: '我应该升级到 QQQ + BOXX 动态对冲，还是保持现状?');
      expect(r.kind, CaptureKind.decision);
      expect(r.confidence, greaterThanOrEqualTo(0.6));
      expect(r.statement, isNotNull);
      expect(r.scope, 'finance/investing');
    });

    test('assumption language upgrades to Assumption candidate', () async {
      final r = await c.classify(text: '假设未来 12 个月美债收益率会下降，TLT 可能跑赢现金。');
      expect(r.kind, CaptureKind.assumption);
      expect(r.scope, 'finance/investing');
    });

    test('principle language upgrades to Principle candidate', () async {
      final r = await c.classify(text: '原则：任何投资仓位都不应该让我晚上睡不着。');
      expect(r.kind, CaptureKind.principle);
    });

    test('concept definition upgrades to Concept candidate', () async {
      final r = await c.classify(text: '安全边际是买入价格低于保守估值的差额。');
      expect(r.kind, CaptureKind.concept);
    });

    test('experiment language upgrades to Experiment candidate', () async {
      final r = await c.classify(text: '实验：接下来 4 周验证早睡是否能提高 HRV，指标是平均 HRV。');
      expect(r.kind, CaptureKind.experiment);
      expect(r.scope, 'health');
    });
  });

  group('HeuristicCaptureClassifier — note fallback', () {
    test('plain sentence with no recurring signal stays a Note', () async {
      final r = await c.classify(text: '今天读了一本关于 FIRE 的书，写得不错。');
      expect(r.kind, CaptureKind.note);
      expect(r.confidence, 0.0);
    });

    test('empty input is a Note with zero confidence', () async {
      final r = await c.classify(text: '   ');
      expect(r.kind, CaptureKind.note);
      expect(r.confidence, 0.0);
    });

    test('numeric pattern without 每/recurring marker stays a Note', () async {
      final r = await c.classify(text: '过去 6 个月持仓涨了 12%');
      expect(r.kind, CaptureKind.note);
    });
  });
}
