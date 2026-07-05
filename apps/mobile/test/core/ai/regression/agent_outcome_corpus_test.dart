import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_corpus.dart';

void main() {
  group('agent outcome regression corpus contract', () {
    test('corpus is non-empty and ids are unique', () {
      expect(agentOutcomeRegressionCorpus, isNotEmpty);
      expect(agentOutcomeRegressionCorpus.length, greaterThanOrEqualTo(8));

      final seen = <String>{};
      for (final c in agentOutcomeRegressionCorpus) {
        expect(seen.add(c.id), isTrue, reason: 'duplicate case id: ${c.id}');
      }
    });

    test('core corpus does not import feature modules', () {
      final src = File(
        'lib/core/ai/regression/agent_outcome_corpus.dart',
      ).readAsStringSync();

      expect(src, isNot(contains('features/')));
      expect(src, isNot(contains('package:naviwealth/features/')));
    });

    test('every case has stable identifiers', () {
      final legalDomains = <String>{
        'finance',
        'health',
        'knowledge',
        'execution',
      };
      for (final c in agentOutcomeRegressionCorpus) {
        expect(c.id, startsWith('${c.domain}.'));
        expect(legalDomains, contains(c.domain), reason: c.id);
        expect(c.agentId, isNotEmpty, reason: c.id);
        expect(c.snapshotId, startsWith('${c.domain}.'));
      }
    });

    test('all LifeOS domains have ready outcome coverage', () {
      final readyDomains = {
        for (final c in agentOutcomeRegressionCorpus)
          if (c.expectedStatus == AgentOutcomeRegressionStatus.ready) c.domain,
      };

      expect(
        readyDomains,
        containsAll(<String>['finance', 'health', 'knowledge', 'execution']),
      );
    });

    test('ready cases declare artifact shape, evidence, and top insights', () {
      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.expectedStatus == AgentOutcomeRegressionStatus.ready,
      )) {
        expect(c.expectedArtifactKind, isNotNull, reason: c.id);
        expect(c.expectedSeverity, isNotNull, reason: c.id);
        expect(c.expectedTopInsightTitles, isNotEmpty, reason: c.id);
        expect(c.expectedEvidenceTypes, isNotEmpty, reason: c.id);
      }
    });

    test('non-ready cases do not claim artifact expectations', () {
      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.expectedStatus != AgentOutcomeRegressionStatus.ready,
      )) {
        expect(c.expectedArtifactKind, isNull, reason: c.id);
        expect(c.expectedSeverity, isNull, reason: c.id);
        expect(c.expectedTopInsightTitles, isEmpty, reason: c.id);
        expect(c.expectedEvidenceTypes, isEmpty, reason: c.id);
      }
    });

    test('status classes and proposal expectations stay represented', () {
      final statuses = {
        for (final c in agentOutcomeRegressionCorpus) c.expectedStatus,
      };
      expect(statuses, containsAll(AgentOutcomeRegressionStatus.values));

      final proposalCases = agentOutcomeRegressionCorpus.where(
        (c) => c.expectedProposalKinds.isNotEmpty,
      );
      expect(proposalCases, isNotEmpty);
    });

    test('required eval tags remain covered', () {
      final tags = {for (final c in agentOutcomeRegressionCorpus) ...c.tags};

      expect(tags, contains(kAgentOutcomeToolFailureTag));
      expect(tags, contains(kAgentOutcomeBudgetExhaustedTag));
      expect(tags, contains(kAgentOutcomeNoLlmProfileTag));
      expect(tags, contains(kAgentOutcomePromptInjectionTag));
      expect(tags, contains(kAgentOutcomeDomainOptOutTag));
    });

    test('risk tags are paired with coherent expected statuses', () {
      for (final c in agentOutcomeRegressionCorpus) {
        if (c.tags.contains(kAgentOutcomeBudgetExhaustedTag)) {
          expect(
            c.expectedStatus,
            AgentOutcomeRegressionStatus.failed,
            reason: c.id,
          );
        }
        if (c.tags.contains(kAgentOutcomeDomainOptOutTag)) {
          expect(
            c.expectedStatus,
            AgentOutcomeRegressionStatus.noFinding,
            reason: c.id,
          );
        }
      }
    });
  });
}
