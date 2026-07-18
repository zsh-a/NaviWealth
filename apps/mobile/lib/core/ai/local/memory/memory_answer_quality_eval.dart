/// Deterministic answer-quality scoring for Memory retrieval evals.
///
/// Vector similarity alone does not prove that a context pack supports a
/// useful answer. This layer scores the observable contract instead:
/// required facts must appear, expected evidence ids must be present, and
/// stale/irrelevant facts or evidence must stay out.
library;

import '../../contracts/context_pack_memory.dart';

final class MemoryAnswerQualityCase {
  const MemoryAnswerQualityCase({
    required this.id,
    required this.question,
    required this.intent,
    this.requiredFacts = const <String>[],
    this.forbiddenFacts = const <String>[],
    this.expectedEvidenceIds = const <String>{},
    this.forbiddenEvidenceIds = const <String>{},
    this.minimumScore = 0.8,
  });

  final String id;
  final String question;
  final ContextIntent intent;
  final List<String> requiredFacts;
  final List<String> forbiddenFacts;
  final Set<String> expectedEvidenceIds;
  final Set<String> forbiddenEvidenceIds;
  final double minimumScore;
}

final class MemoryAnswerQualityResult {
  const MemoryAnswerQualityResult({
    required this.score,
    required this.missingFacts,
    required this.forbiddenFactsFound,
    required this.missingEvidenceIds,
    required this.forbiddenEvidenceIdsFound,
    required this.minimumScore,
  });

  final double score;
  final List<String> missingFacts;
  final List<String> forbiddenFactsFound;
  final Set<String> missingEvidenceIds;
  final Set<String> forbiddenEvidenceIdsFound;
  final double minimumScore;

  bool get passed =>
      score >= minimumScore &&
      missingFacts.isEmpty &&
      forbiddenFactsFound.isEmpty &&
      missingEvidenceIds.isEmpty &&
      forbiddenEvidenceIdsFound.isEmpty;
}

/// Privacy-safe aggregate emitted by the deterministic answer-quality gate.
///
/// Case ids are stable fixture identifiers. Answers, questions, facts,
/// evidence ids, and retrieved user content are deliberately excluded.
final class MemoryAnswerQualityReport {
  MemoryAnswerQualityReport.fromResults(
    Map<String, MemoryAnswerQualityResult> results,
  ) : caseCount = results.length,
      passedCaseCount = results.values.where((result) => result.passed).length,
      forbiddenClaimFailures = results.values
          .where((result) => result.forbiddenFactsFound.isNotEmpty)
          .length,
      forbiddenEvidenceFailures = results.values
          .where((result) => result.forbiddenEvidenceIdsFound.isNotEmpty)
          .length,
      missingFactFailures = results.values
          .where((result) => result.missingFacts.isNotEmpty)
          .length,
      missingEvidenceFailures = results.values
          .where((result) => result.missingEvidenceIds.isNotEmpty)
          .length,
      failedCaseIds = <String>[
        for (final entry in results.entries)
          if (!entry.value.passed) entry.key,
      ]..sort();

  final int caseCount;
  final int passedCaseCount;
  final int forbiddenClaimFailures;
  final int forbiddenEvidenceFailures;
  final int missingFactFailures;
  final int missingEvidenceFailures;
  final List<String> failedCaseIds;

  bool get passed => caseCount > 0 && passedCaseCount == caseCount;
  double get passRate => caseCount == 0 ? 0 : passedCaseCount / caseCount;

  Map<String, Object> toJson() => <String, Object>{
    'case_count': caseCount,
    'passed_case_count': passedCaseCount,
    'pass_rate': passRate,
    'forbidden_claim_failures': forbiddenClaimFailures,
    'forbidden_evidence_failures': forbiddenEvidenceFailures,
    'missing_fact_failures': missingFactFailures,
    'missing_evidence_failures': missingEvidenceFailures,
    'failed_case_ids': failedCaseIds,
    'passed': passed,
  };
}

Set<String> memoryAnswerEvidenceIds(ContextPackMemory pack) => <String>{
  for (final memory in pack.userPreferences) memory.id,
  for (final memory in pack.relatedDecisions) memory.id,
  for (final memory in pack.applicableRules) memory.id,
  for (final event in pack.recentEvents) event.id,
  for (final event in pack.relatedEvents) event.id,
};

MemoryAnswerQualityResult scoreMemoryAnswerQuality({
  required MemoryAnswerQualityCase evalCase,
  required String answer,
  required ContextPackMemory context,
}) {
  final normalizedAnswer = _normalize(answer);
  final missingFacts = [
    for (final fact in evalCase.requiredFacts)
      if (!normalizedAnswer.contains(_normalize(fact))) fact,
  ];
  final forbiddenFactsFound = [
    for (final fact in evalCase.forbiddenFacts)
      if (normalizedAnswer.contains(_normalize(fact))) fact,
  ];
  final evidence = memoryAnswerEvidenceIds(context);
  final missingEvidence = evalCase.expectedEvidenceIds.difference(evidence);
  final forbiddenEvidence = evalCase.forbiddenEvidenceIds.intersection(
    evidence,
  );

  final componentScores = <double>[
    if (evalCase.requiredFacts.isNotEmpty)
      (evalCase.requiredFacts.length - missingFacts.length) /
          evalCase.requiredFacts.length,
    if (evalCase.expectedEvidenceIds.isNotEmpty)
      (evalCase.expectedEvidenceIds.length - missingEvidence.length) /
          evalCase.expectedEvidenceIds.length,
  ];
  final recall = componentScores.isEmpty
      ? 1.0
      : componentScores.reduce((a, b) => a + b) / componentScores.length;
  final penalty =
      (forbiddenFactsFound.length + forbiddenEvidence.length) * 0.25;
  final score = (recall - penalty).clamp(0.0, 1.0);
  return MemoryAnswerQualityResult(
    score: score,
    missingFacts: missingFacts,
    forbiddenFactsFound: forbiddenFactsFound,
    missingEvidenceIds: missingEvidence,
    forbiddenEvidenceIdsFound: forbiddenEvidence,
    minimumScore: evalCase.minimumScore,
  );
}

String _normalize(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
