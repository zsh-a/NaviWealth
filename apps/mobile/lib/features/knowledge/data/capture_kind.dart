/// Capture target type (`docs/knowledgeos-domain.md` §3 + §14.2 P1).
///
/// Tiny enum lifted out of `capture_classifier.dart` so both the
/// classifier and the `propose_capture` AI tool depend on the same
/// wire-stable strings without one importing the other's heuristic body.
library;

import '../domain/knowledge_models.dart' show parseEnumByName;

enum CaptureKind {
  note,
  routine,
  decision,
  principle,
  assumption,
  concept,
  experiment;

  String get wire => name;

  static CaptureKind parse(String s) =>
      parseEnumByName(values, s, CaptureKind.note);
}
