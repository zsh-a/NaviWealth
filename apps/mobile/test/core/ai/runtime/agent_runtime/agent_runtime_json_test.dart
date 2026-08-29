import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';

void main() {
  group('agentRuntimeObjectOrNull', () {
    test('passes through typed object maps', () {
      const value = <String, Object?>{'id': 'a'};
      expect(agentRuntimeObjectOrNull(value), same(value));
    });

    test('converts dynamic maps to string-keyed objects', () {
      final value = <dynamic, dynamic>{'id': 'a', 2: 'b'};
      expect(agentRuntimeObjectOrNull(value), <String, Object?>{
        'id': 'a',
        '2': 'b',
      });
    });

    test('returns null for non-map values', () {
      expect(agentRuntimeObjectOrNull(null), isNull);
      expect(agentRuntimeObjectOrNull(<Object?>['a']), isNull);
      expect(agentRuntimeObjectOrNull('object'), isNull);
    });
  });

  group('agentRuntimeIntOrNull', () {
    test('accepts nums', () {
      expect(agentRuntimeIntOrNull(3), 3);
      expect(agentRuntimeIntOrNull(2.0), 2);
    });

    test('returns null for absent or non-numeric values', () {
      expect(agentRuntimeIntOrNull(null), isNull);
      expect(agentRuntimeIntOrNull('3'), isNull);
      expect(agentRuntimeIntOrNull(true), isNull);
    });
  });

  group('agentRuntimeDateTimeOrNull', () {
    test('parses ISO-8601 strings to UTC', () {
      expect(
        agentRuntimeDateTimeOrNull('2026-06-29T08:00:00.000Z'),
        DateTime.utc(2026, 6, 29, 8),
      );
      expect(
        agentRuntimeDateTimeOrNull('2026-06-29T08:00:00.000+02:00'),
        DateTime.utc(2026, 6, 29, 6),
      );
    });

    test('returns null for absent, empty, or unparseable values', () {
      expect(agentRuntimeDateTimeOrNull(null), isNull);
      expect(agentRuntimeDateTimeOrNull(''), isNull);
      expect(agentRuntimeDateTimeOrNull('not-a-date'), isNull);
      expect(agentRuntimeDateTimeOrNull(12345), isNull);
    });
  });
}
