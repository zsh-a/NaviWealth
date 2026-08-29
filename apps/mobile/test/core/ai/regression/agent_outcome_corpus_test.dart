import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/intent/intent.dart'
    show IntentDescriptor, intentAllowsDomain;
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
      final src = File('lib/core/ai/regression/agent_outcome_corpus.dart')
          .readAsStringSync();

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
        containsAll(<String>['finance', 'health', 'execution']),
      );
    });

    test('FinanceOS first-batch agents have ready outcome coverage', () {
      final financeReadyAgentIds = {
        for (final c in agentOutcomeRegressionCorpus)
          if (c.domain == 'finance' &&
              c.expectedStatus == AgentOutcomeRegressionStatus.ready)
            c.agentId,
      };

      expect(
        financeReadyAgentIds,
        containsAll(<String>{
          'weekly_wealth_review',
          'cashflow_anomaly_review',
          'fire_plan_drift_monitor',
          'options_income_risk_review',
        }),
      );
    });

    test('FinanceOS outcome cases point at executable agent fixtures', () {
      const executableFixturePaths = <String, String>{
        'weekly_wealth_review':
            'test/features/finance/agents/weekly_wealth_review_agent_test.dart',
        'cashflow_anomaly_review': 'test/features/finance/agents/cashflow_anomaly_review_agent_test.dart',
        'fire_plan_drift_monitor': 'test/features/finance/agents/fire_plan_drift_monitor_agent_test.dart',
        'options_income_risk_review': 'test/features/finance/agents/options_income_risk_review_agent_test.dart',
      };

      for (final c in agentOutcomeRegressionCorpus.where(
        (c) =>
            c.domain == 'finance' &&
            c.expectedStatus == AgentOutcomeRegressionStatus.ready,
      )) {
        final path = executableFixturePaths[c.agentId];
        expect(path, isNotNull, reason: c.id);
        expect(File(path!).existsSync(), isTrue, reason: c.id);
      }
    });

    test('all corpus agent ids point at executable fixture files', () {
      const executableFixturePaths = <String, String>{
        'weekly_wealth_review':
            'test/features/finance/agents/weekly_wealth_review_agent_test.dart',
        'cashflow_anomaly_review': 'test/features/finance/agents/cashflow_anomaly_review_agent_test.dart',
        'fire_plan_drift_monitor': 'test/features/finance/agents/fire_plan_drift_monitor_agent_test.dart',
        'options_income_risk_review': 'test/features/finance/agents/options_income_risk_review_agent_test.dart',
        'recovery_alert':
            'test/features/health/agents/recovery_alert_agent_test.dart',
        'weekly_summary':
            'test/features/health/agents/weekly_summary_agent_test.dart',
        'execution_review':
            'test/features/execution/agents/review_agent_test.dart',
        'execution_due_actions':
            'test/features/execution/agents/due_action_agent_test.dart',
      };

      for (final c in agentOutcomeRegressionCorpus) {
        final path = executableFixturePaths[c.agentId];
        expect(path, isNotNull, reason: c.id);
        expect(File(path!).existsSync(), isTrue, reason: c.id);
      }
    });

    test('all corpus cases are wired to executable evaluator fixtures', () {
      const executableFixturePaths = <String, String>{
        'weekly_wealth_review':
            'test/features/finance/agents/weekly_wealth_review_agent_test.dart',
        'cashflow_anomaly_review': 'test/features/finance/agents/cashflow_anomaly_review_agent_test.dart',
        'fire_plan_drift_monitor': 'test/features/finance/agents/fire_plan_drift_monitor_agent_test.dart',
        'options_income_risk_review': 'test/features/finance/agents/options_income_risk_review_agent_test.dart',
        'recovery_alert':
            'test/features/health/agents/recovery_alert_agent_test.dart',
        'weekly_summary':
            'test/features/health/agents/weekly_summary_agent_test.dart',
        'execution_review':
            'test/features/execution/agents/review_agent_test.dart',
        'execution_due_actions':
            'test/features/execution/agents/due_action_agent_test.dart',
      };
      for (final c in agentOutcomeRegressionCorpus) {
        final path = executableFixturePaths[c.agentId];
        expect(path, isNotNull, reason: c.id);
        final src = File(path!).readAsStringSync();
        expect(src, contains(c.id), reason: c.id);
        expect(src, contains('evaluateAgentOutcomeCase'), reason: c.id);
      }
    });

    test('ready cases declare artifact shape, evidence, and top insights', () {
      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.expectedStatus == AgentOutcomeRegressionStatus.ready,
      )) {
        expect(c.expectedArtifactKind, isNotNull, reason: c.id);
        expect(c.expectedSeverity, isNotNull, reason: c.id);
        expect(c.expectedTopInsightTitles, isNotEmpty, reason: c.id);
        expect(c.expectedEvidenceTypes, isNotEmpty, reason: c.id);
        expect(c.expectedActionKinds, isNotEmpty, reason: c.id);
        expect(
          c.expectedActionIntents.isNotEmpty ||
              c.expectedActionRoutes.isNotEmpty,
          isTrue,
          reason: c.id,
        );
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
        expect(c.expectedActionKinds, isEmpty, reason: c.id);
        expect(c.expectedActionIntents, isEmpty, reason: c.id);
        expect(c.expectedActionRoutes, isEmpty, reason: c.id);
      }
    });

    test(
      'ready action kinds stay within the unified artifact action model',
      () {
        const allowedActionKinds = <String>{
          'review',
          'proposal',
          'open_object',
          'open_route',
        };

        for (final c in agentOutcomeRegressionCorpus.where(
          (c) => c.expectedStatus == AgentOutcomeRegressionStatus.ready,
        )) {
          expect(
            allowedActionKinds.containsAll(c.expectedActionKinds),
            isTrue,
            reason: c.id,
          );
        }
      },
    );

    test('route actions declare a canonical in-app destination', () {
      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.expectedStatus == AgentOutcomeRegressionStatus.ready,
      )) {
        expect(c.expectedActionRoutes, isNotEmpty, reason: c.id);
        for (final route in c.expectedActionRoutes) {
          expect(route, startsWith('/'), reason: c.id);
        }
      }
    });

    test('ready action intents are registered for agent artifacts', () {
      final descriptorsByName = <String, IntentDescriptor>{};
      for (final descriptor in const <IntentDescriptor>[
        ...kFinanceAgentIntentDescriptors,
        ...kHealthAgentIntentDescriptors,
        ...kExecutionAgentIntentDescriptors,
      ]) {
        descriptorsByName.putIfAbsent(descriptor.name, () => descriptor);
      }

      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.expectedStatus == AgentOutcomeRegressionStatus.ready,
      )) {
        for (final intent in c.expectedActionIntents) {
          final descriptor = descriptorsByName[intent];
          expect(descriptor, isNotNull, reason: '${c.id}: $intent');
          expect(
            intentAllowsDomain(descriptor!, c.domain),
            isTrue,
            reason: '${c.id}: $intent',
          );
          expect(
            descriptor.allowedObjectTypes,
            contains(kAgentArtifactObjectType),
            reason: '${c.id}: $intent',
          );
        }
      }
    });

    test(
      'FinanceOS agent actions stay follow-up or direct navigation only',
      () {
        const financeFollowUpIntents = <String>{
          kAgentExplainResultIntent,
          kFinanceReviewWealthIntent,
        };

        for (final c in agentOutcomeRegressionCorpus.where(
          (c) =>
              c.domain == 'finance' &&
              c.expectedStatus == AgentOutcomeRegressionStatus.ready,
        )) {
          expect(
            c.expectedActionIntents.isNotEmpty ||
                c.expectedActionRoutes.isNotEmpty,
            isTrue,
            reason: c.id,
          );
          expect(
            financeFollowUpIntents.containsAll(c.expectedActionIntents),
            isTrue,
            reason: c.id,
          );
          expect(
            c.expectedActionRoutes.every((route) => route.startsWith('/')),
            isTrue,
            reason: c.id,
          );
          expect(c.expectedProposalKinds, isEmpty, reason: c.id);
        }
      },
    );

    test('status classes stay represented', () {
      final statuses = {
        for (final c in agentOutcomeRegressionCorpus) c.expectedStatus,
      };
      expect(statuses, containsAll(AgentOutcomeRegressionStatus.values));
    });

    test('required eval tags remain covered', () {
      final tags = {for (final c in agentOutcomeRegressionCorpus) ...c.tags};

      expect(tags, contains(kAgentOutcomeBudgetExhaustedTag));
      expect(tags, contains(kAgentOutcomeNoLlmProfileTag));
    });

    test('FinanceOS has executable no-LLM fallback coverage', () {
      final financeNoLlmCases = agentOutcomeRegressionCorpus.where(
        (c) =>
            c.domain == 'finance' &&
            c.tags.contains(kAgentOutcomeNoLlmProfileTag),
      );

      expect(
        financeNoLlmCases.map((c) => c.agentId),
        containsAll(<String>{
          'weekly_wealth_review',
          'cashflow_anomaly_review',
          'fire_plan_drift_monitor',
          'options_income_risk_review',
        }),
      );
      expect(
        financeNoLlmCases.map((c) => c.expectedStatus),
        everyElement(AgentOutcomeRegressionStatus.ready),
      );
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
      }
    });

    test('tagged risk cases are wired to executable evaluator fixtures', () {
      const fixturePathsByCaseId = <String, String>{
        'finance.weekly_wealth_review.no_llm_profile_fallback':
            'test/features/finance/agents/weekly_wealth_review_agent_test.dart',
        'finance.cashflow_anomaly_review.no_llm_profile_fallback': 'test/features/finance/agents/cashflow_anomaly_review_agent_test.dart',
        'finance.fire_plan_drift_monitor.no_llm_profile_fallback': 'test/features/finance/agents/fire_plan_drift_monitor_agent_test.dart',
        'finance.options_income_risk_review.no_llm_profile_fallback': 'test/features/finance/agents/options_income_risk_review_agent_test.dart',
        'knowledge.inbox_triage.ready':
            'test/features/knowledge/agents/inbox_triage_agent_test.dart',
        'knowledge.contradiction.prompt_injection_guard':
            'test/features/knowledge/agents/contradiction_agent_test.dart',
        'knowledge.review.tool_failure_fallback':
            'test/features/knowledge/agents/review_agent_test.dart',
        'execution.review.budget_exhausted':
            'test/features/execution/agents/review_agent_test.dart',
      };

      for (final c in agentOutcomeRegressionCorpus.where(
        (c) => c.tags.isNotEmpty,
      )) {
        final path = fixturePathsByCaseId[c.id];
        expect(path, isNotNull, reason: c.id);
        final src = File(path!).readAsStringSync();
        expect(src, contains(c.id), reason: c.id);
        expect(src, contains('evaluateAgentOutcomeCase'), reason: c.id);
      }
    });
  });
}
