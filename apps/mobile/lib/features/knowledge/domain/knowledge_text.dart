/// Shared KnowledgeOS text-display helpers.
///
/// Kept out of `ui/_widgets.dart` so composition providers can reuse the same
/// excerpt rules without importing widget code.
library;

/// Max chars shown for a body / summary / rationale excerpt in compact UI.
const int kKnowledgeExcerptMaxChars = 200;

/// Short headline excerpt derived from the shared excerpt budget.
const int kKnowledgeHeadlineExcerptMaxChars = kKnowledgeExcerptMaxChars ~/ 3;

/// Supporting-detail excerpt derived from the shared excerpt budget.
const int kKnowledgeSupportingExcerptMaxChars =
    kKnowledgeExcerptMaxChars - kKnowledgeHeadlineExcerptMaxChars;

/// Truncate [text] to [max] chars with a trailing ellipsis.
String knowledgeExcerpt(String text, {int max = kKnowledgeExcerptMaxChars}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;
