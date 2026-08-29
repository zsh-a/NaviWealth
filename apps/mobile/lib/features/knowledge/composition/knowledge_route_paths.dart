/// KnowledgeOS route path contract.
library;

abstract final class KnowledgeRoutes {
  static const inbox = '/knowledge';
  static const library = '/knowledge/library';
  static const noteDetail = '/knowledge/library/note/:id';
  static const decisionDetail = '/knowledge/library/decision/:id';

  static String note(String id) =>
      '/knowledge/library/note/${Uri.encodeComponent(id)}';

  static String decision(String id) =>
      '/knowledge/library/decision/${Uri.encodeComponent(id)}';
}

abstract final class KnowledgeRouteNames {
  static const inbox = 'knowledge-inbox';
  static const library = 'knowledge-library';
  static const noteDetail = 'knowledge-note-detail';
  static const decisionDetail = 'knowledge-decision-detail';
}
