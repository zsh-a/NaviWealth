import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/freshness/freshness_gate.dart';

void main() {
  group('isStale', () {
    test('returns false when device behind cloud (HLC <)', () {
      const cloud = Freshness(
        readModel: 'monthly_spend_by_category',
        sourceHlcWatermark: '00000001700000000000.0001-server',
        refreshedAt: '2026-05-12T10:00:00Z',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      // Device HLC strictly less (smaller wallMillis).
      const local = '00000001699000000000.0001-device';
      expect(isStale(cloud: cloud, localHlcText: local), isFalse);
    });

    test('returns true when device ahead of cloud (HLC >)', () {
      const cloud = Freshness(
        readModel: 'monthly_spend_by_category',
        sourceHlcWatermark: '00000001700000000000.0001-server',
        refreshedAt: '2026-05-12T10:00:00Z',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      const local = '00000001700500000000.0001-device';
      expect(isStale(cloud: cloud, localHlcText: local), isTrue);
    });

    test('returns false when HLCs are equal', () {
      const watermark = '00000001700000000000.0001-server';
      const cloud = Freshness(
        readModel: 'r',
        sourceHlcWatermark: watermark,
        refreshedAt: 't',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      expect(isStale(cloud: cloud, localHlcText: watermark), isFalse);
    });

    test('returns false when local HLC is empty (device pre-stamp)', () {
      const cloud = Freshness(
        readModel: 'r',
        sourceHlcWatermark: '00000001700000000000.0001-server',
        refreshedAt: 't',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      expect(isStale(cloud: cloud, localHlcText: ''), isFalse);
    });

    test('returns false when watermark is empty (cloud never refreshed)', () {
      const cloud = Freshness(
        readModel: 'r',
        sourceHlcWatermark: '',
        refreshedAt: '',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      expect(
        isStale(
          cloud: cloud,
          localHlcText: '00000001700000000000.0001-device',
        ),
        isFalse,
      );
    });
  });
}
