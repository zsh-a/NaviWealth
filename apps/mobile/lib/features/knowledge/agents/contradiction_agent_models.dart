part of 'contradiction_agent.dart';

class _Contradiction {
  const _Contradiction({
    required this.decisionId,
    required this.decisionQuestion,
    required this.kind,
    required this.referenceId,
    required this.detail,
  });
  final String decisionId;
  final String decisionQuestion;
  final String kind;
  final String referenceId;
  final String detail;
}

/// A cosine-recalled candidate memory for check-2, pre-judge.
class _Candidate {
  const _Candidate({
    required this.referenceId,
    required this.question,
    required this.text,
    required this.cosine,
    required this.overlap,
  });
  final String referenceId;
  final String question;
  final String text;
  final double cosine;
  final double overlap;
}
