import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/regression/agent_policy_corpus.dart';

void main() {
  test('attention policy corpus has unique executable cases', () {
    final ids = agentPolicyRegressionCorpus.map((item) => item.id).toSet();
    expect(ids, hasLength(agentPolicyRegressionCorpus.length));

    for (final regressionCase in agentPolicyRegressionCorpus) {
      final failures = evaluateAgentPolicyRegressionCase(
        regressionCase,
        at: DateTime.utc(2026, 8, 23, 8),
      );
      expect(failures, isEmpty, reason: '${regressionCase.id}: $failures');
    }
  });
}
