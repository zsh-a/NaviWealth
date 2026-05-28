import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/capture_classifier.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';

void main() {
  const c = CaptureClassifier();

  group('CaptureClassifier — routine detection', () {
    test('港卡需要定期活跃 (no explicit interval) — routine with default 180d',
        () {
      final r = c.classify(text: '港卡需要定期做一次活跃交易，否则会休眠。');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.scope, 'finance/cards');
      expect(r.confidence, greaterThan(0.5));
      expect(r.statement, isNotNull);
    });

    test('"每 6 个月做一次" — explicit interval parsed', () {
      final r = c.classify(text: '港卡每 6 个月做一次活跃交易');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 180);
      expect(r.confidence, greaterThanOrEqualTo(0.8));
    });

    test('"每 90 天" — pure-day interval', () {
      final r = c.classify(text: '每 90 天做一次 portfolio 复盘');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 90);
    });

    test('"每年报税" — year interval', () {
      final r = c.classify(text: '每年报税前对一遍账');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 365);
      expect(r.scope, 'finance/tax');
    });

    test('"每周做一次 review" — weekly cadence', () {
      final r = c.classify(text: '每周做一次 portfolio review');
      expect(r.kind, CaptureKind.routine);
      expect(r.intervalDays, 7);
    });

    test('English "every 6 months" recurring marker fires', () {
      final r = c.classify(text: 'Activate HK card every 6 months.');
      expect(r.kind, CaptureKind.routine);
      // Marker-only (no Chinese 每 N 单位 regex match) — interval falls
      // back to default 180.
      expect(r.intervalDays, 180);
    });

    test('体检 + scope guess', () {
      final r = c.classify(text: '每年做一次体检');
      expect(r.kind, CaptureKind.routine);
      expect(r.scope, 'health');
    });

    test('statement is trimmed and length-capped', () {
      final long = '港卡需要定期 ' * 30;
      final r = c.classify(text: long);
      expect(r.kind, CaptureKind.routine);
      expect(r.statement!.length, lessThanOrEqualTo(61));
    });
  });

  group('CaptureClassifier — note fallback', () {
    test('plain sentence with no recurring signal stays a Note', () {
      final r = c.classify(text: '今天读了一本关于 FIRE 的书，写得不错。');
      expect(r.kind, CaptureKind.note);
      expect(r.confidence, 0.0);
    });

    test('empty input is a Note with zero confidence', () {
      final r = c.classify(text: '   ');
      expect(r.kind, CaptureKind.note);
      expect(r.confidence, 0.0);
    });

    test('decision-style language alone does not fire (heuristic未上线)', () {
      // Slice B v1 only ships the routine heuristic. A decision-shaped
      // capture stays a Note until the §14.2 P1 decision heuristic
      // lands. This test pins that scope; flip when the heuristic lands.
      final r = c.classify(
        text: '我应该升级到 QQQ + BOXX 动态对冲，还是保持现状?',
      );
      expect(r.kind, CaptureKind.note);
    });

    test('numeric pattern without 每/recurring marker stays a Note', () {
      final r = c.classify(text: '过去 6 个月持仓涨了 12%');
      expect(r.kind, CaptureKind.note);
    });
  });
}
