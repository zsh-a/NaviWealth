import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  group('Freshness wire format', () {
    test('snake_case roundtrip matches Rust mirror', () {
      const f = Freshness(
        readModel: 'monthly_spend_by_category',
        sourceHlcWatermark: '01939abc-0000-feed',
        refreshedAt: '2026-05-11T10:00:00Z',
        schemaVersion: 1,
        calculationVersion: 1,
      );
      final encoded = jsonEncode(f.toJson());
      final json = jsonDecode(encoded) as Map<String, Object?>;
      expect(json['read_model'], 'monthly_spend_by_category');
      expect(json['source_hlc_watermark'], '01939abc-0000-feed');
      expect(json['refreshed_at'], '2026-05-11T10:00:00Z');
      expect(json['schema_version'], 1);
      expect(json['calculation_version'], 1);

      final decoded = Freshness.fromJson(json);
      expect(decoded.readModel, f.readModel);
      expect(decoded.sourceHlcWatermark, f.sourceHlcWatermark);
      expect(decoded.refreshedAt, f.refreshedAt);
      expect(decoded.schemaVersion, f.schemaVersion);
      expect(decoded.calculationVersion, f.calculationVersion);
    });
  });

  group('Freshness.tryFromOutput', () {
    test('extracts freshness when nested in tool output', () {
      final output = <String, Object?>{
        'rows': const <Object?>[],
        'summary': <String, Object?>{},
        'freshness': const <String, Object?>{
          'read_model': 'monthly_spend_by_category',
          'source_hlc_watermark': '01939...',
          'refreshed_at': '2026-05-11T10:00:00Z',
          'schema_version': 1,
          'calculation_version': 1,
        },
      };
      final f = Freshness.tryFromOutput(output);
      expect(f, isNotNull);
      expect(f!.readModel, 'monthly_spend_by_category');
      expect(f.schemaVersion, 1);
    });

    test('returns null for legacy tools without freshness', () {
      final output = <String, Object?>{
        'rows': const <Object?>[],
        'approximation': true,
      };
      expect(Freshness.tryFromOutput(output), isNull);
    });

    test('returns null when output is not a map', () {
      expect(Freshness.tryFromOutput(null), isNull);
      expect(Freshness.tryFromOutput('string'), isNull);
      expect(Freshness.tryFromOutput(42), isNull);
    });

    test('handles partial / malformed freshness gracefully', () {
      final output = <String, Object?>{
        'freshness': <String, Object?>{
          // missing schema_version/calculation_version, etc.
          'read_model': 'partial',
        },
      };
      final f = Freshness.tryFromOutput(output);
      expect(f, isNotNull);
      expect(f!.readModel, 'partial');
      expect(f.schemaVersion, 0);
      expect(f.sourceHlcWatermark, '');
    });
  });
}
