import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';

void main() {
  group('EvidenceAnchor', () {
    test('toJson emits snake_case wire keys and omits null label', () {
      const a = EvidenceAnchor(entityTable: 'postings', entityId: 'p_123');
      expect(a.toJson(), <String, Object?>{
        'entity_table': 'postings',
        'entity_id': 'p_123',
      });
    });

    test('toJson includes label when present', () {
      const a = EvidenceAnchor(
        entityTable: 'assets',
        entityId: 'a_1',
        label: 'Apple Inc.',
      );
      final json = a.toJson();
      expect(json['label'], 'Apple Inc.');
    });

    test('fromJson roundtrips a fully populated anchor', () {
      const a = EvidenceAnchor(
        entityTable: 'journal_entries',
        entityId: 'je_42',
        label: '2026-05-12 餐饮',
      );
      final encoded = jsonEncode(a.toJson());
      final decoded = EvidenceAnchor.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(decoded.entityTable, a.entityTable);
      expect(decoded.entityId, a.entityId);
      expect(decoded.label, a.label);
    });
  });

  group('withEvidence', () {
    test('attaches an empty evidence list when no anchors are supplied', () {
      final out = withEvidence(
        result: const <String, Object?>{'count': 0},
        anchors: const [],
      );
      expect(out['count'], 0);
      expect(out['evidence'], isEmpty);
    });

    test('preserves the original result and appends evidence list', () {
      final out = withEvidence(
        result: const <String, Object?>{'count': 2},
        anchors: const [
          EvidenceAnchor(entityTable: 'postings', entityId: 'p1'),
          EvidenceAnchor(entityTable: 'postings', entityId: 'p2'),
        ],
      );
      expect(out['count'], 2);
      final evidence = out['evidence']! as List;
      expect(evidence, hasLength(2));
      expect((evidence.first as Map)['entity_id'], 'p1');
    });
  });

  group('readEvidence', () {
    test('returns empty for envelopes without an evidence key', () {
      expect(readEvidence(const <String, Object?>{'count': 0}), isEmpty);
    });

    test('parses well-formed entries and skips bad rows', () {
      final envelope = <String, Object?>{
        'evidence': <Object?>[
          <String, Object?>{
            'entity_table': 'postings',
            'entity_id': 'p1',
            'label': 'meal',
          },
          // Missing entity_id → dropped.
          <String, Object?>{'entity_table': 'postings'},
          // Empty entity_table → dropped.
          <String, Object?>{'entity_table': '', 'entity_id': 'p2'},
          // Wrong type → dropped (defensive).
          'not-an-object',
          // Another valid one to make sure the iterator survives bad rows.
          <String, Object?>{'entity_table': 'assets', 'entity_id': 'a1'},
        ],
      };
      final out = readEvidence(envelope);
      expect(out, hasLength(2));
      expect(out.map((a) => a.entityId), ['p1', 'a1']);
      expect(out.first.label, 'meal');
      expect(out.last.label, isNull);
    });
  });
}
