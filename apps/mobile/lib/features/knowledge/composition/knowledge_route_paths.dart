/// KnowledgeOS route path contract.
library;

abstract final class KnowledgeRoutes {
  static const inbox = '/knowledge';
  static const library = '/knowledge/library';
  static const review = '/knowledge/review';
  static const decisionDetail = '/knowledge/library/decision/:id';
  static const objectDetail = '/knowledge/library/object/:kind/:id';

  static String decision(String id) =>
      '/knowledge/library/decision/${Uri.encodeComponent(id)}';

  static String object(String kind, String id) =>
      '/knowledge/library/object/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}';
}

abstract final class KnowledgeRouteNames {
  static const inbox = 'knowledge-inbox';
  static const library = 'knowledge-library';
  static const review = 'knowledge-review';
  static const decisionDetail = 'knowledge-decision-detail';
  static const objectDetail = 'knowledge-object-detail';
}
