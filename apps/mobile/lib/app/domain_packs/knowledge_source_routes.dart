import '../../features/knowledge/composition/knowledge_route_paths.dart';

String? knowledgeSourceRoute(String family, String rowId) {
  if (family == 'know:knowledge_notes') return KnowledgeRoutes.note(rowId);
  if (family == 'know:knowledge_decisions') {
    return KnowledgeRoutes.decision(rowId);
  }
  return null;
}
