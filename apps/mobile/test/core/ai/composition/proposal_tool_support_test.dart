import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_envelope.dart'
    as envelope;
import 'package:naviwealth/core/ai/composition/proposal_tool_support.dart';
import 'package:naviwealth/features/execution/ai_tools/_tool_support.dart'
    as execution_support;
import 'package:naviwealth/features/knowledge/ai_tools/_tool_support.dart'
    as knowledge_support;

void main() {
  group('proposalEnvelope', () {
    test('defaults to the shared confirmation note and ready status', () {
      final body = proposalEnvelope(
        kind: 'knowledge_capture_note',
        summaryZh: '记一笔',
        payload: <String, Object?>{'id': 'n1'},
      );

      expect(body['status'], 'ready');
      expect(body['kind'], 'knowledge_capture_note');
      expect(body['summary_zh'], '记一笔');
      expect(body['payload'], <String, Object?>{'id': 'n1'});
      expect(body['note'], kProposalConfirmNote);
      expect(body['proposal_id'], isNotEmpty);
      expect(body['interaction'], isA<Map<String, Object?>>());
    });

    test('forwards a tool-specific note to the envelope', () {
      final body = proposalEnvelope(
        kind: 'execution_create_plan',
        summaryZh: '建计划',
        payload: const <String, Object?>{},
        note: 'commits to repository.createPlan',
      );

      expect(body['note'], 'commits to repository.createPlan');
    });
  });

  test('badRequest returns a returned-not-thrown error body', () {
    expect(badRequest('invalid priority'), <String, Object?>{
      'error': 'invalid priority',
      'code': 'bad_request',
    });
  });

  test('notFound carries the offending ids', () {
    expect(notFound('unknown ids', <String>['a', 'b']), <String, Object?>{
      'error': 'unknown ids',
      'code': 'not_found',
      'missing': <String>['a', 'b'],
    });
  });

  test('domain tool-support re-exports share one envelope contract', () {
    // Both domains used to keep private copies of these wrappers; pin them to
    // identical behavior so a future edit cannot silently fork the contract.
    const kind = 'shared_contract_probe';
    const payload = <String, Object?>{'id': 'x'};

    final coreBody = proposalEnvelope(
      kind: kind,
      summaryZh: '一致',
      payload: payload,
    );
    final knowledgeBody = knowledge_support.proposalEnvelope(
      kind: kind,
      summaryZh: '一致',
      payload: payload,
    );
    final executionBody = execution_support.proposalEnvelope(
      kind: kind,
      summaryZh: '一致',
      payload: payload,
    );

    expect(knowledgeBody['status'], coreBody['status']);
    expect(knowledgeBody['note'], coreBody['note']);
    expect(executionBody['status'], coreBody['status']);
    expect(executionBody['note'], coreBody['note']);

    expect(
      knowledge_support.badRequest('bad'),
      envelope.proposalBadRequest('bad'),
    );
    expect(
      execution_support.badRequest('bad'),
      envelope.proposalBadRequest('bad'),
    );
    expect(
      knowledge_support.kProposalConfirmNote,
      envelope.kProposalConfirmNote,
    );
  });
}
