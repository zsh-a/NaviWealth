/// Capture target type (`docs/knowledgeos-domain.md` §3 + §14.2 P1).
///
/// Tiny enum lifted out of `capture_classifier.dart` so both the
/// classifier and the `propose_capture` AI tool depend on the same
/// wire-stable strings without one importing the other's heuristic body.
library;

enum CaptureKind {
  note,
  routine,
  decision,
  principle,
  assumption,
  concept,
  experiment;

  String get wire => name;

  static CaptureKind parse(String s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return CaptureKind.note;
  }
}
