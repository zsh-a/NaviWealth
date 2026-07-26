part of 'contradiction_agent.dart';

class _Contradiction {
  const _Contradiction({
    required this.findingId,
    required this.subjectKind,
    required this.decisionId,
    required this.decisionQuestion,
    required this.kind,
    required this.referenceId,
    required this.detail,
    required this.confidence,
    this.semanticSimilarity,
    this.tokenOverlap,
  });
  final String findingId;
  final String subjectKind;
  final String decisionId;
  final String decisionQuestion;
  final String kind;
  final String referenceId;
  final String detail;
  final double confidence;
  final double? semanticSimilarity;
  final double? tokenOverlap;
}

/// A cosine-recalled candidate memory for check-2, pre-judge.
class _Candidate {
  const _Candidate({
    required this.referenceId,
    required this.subjectKind,
    required this.question,
    required this.text,
    required this.cosine,
    required this.overlap,
  });
  final String referenceId;
  final String subjectKind;
  final String question;
  final String text;
  final double cosine;
  final double overlap;
}
