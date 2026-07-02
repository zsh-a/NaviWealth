/// KnowledgeOS route path contract.
library;

abstract final class KnowledgeRoutes {
  static const inbox = '/knowledge';
  static const library = '/knowledge/library';
  static const review = '/knowledge/review';
  static const decisionDetail = '/knowledge/library/decision/:id';
  static const objectDetail = '/knowledge/library/object/:kind/:id';
}
