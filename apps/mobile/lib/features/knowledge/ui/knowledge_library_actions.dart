part of 'knowledge_library_page.dart';

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  await ref.read(knowledgeRepositoryProvider.future);
}

Future<void> _deleteEntry({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeRepository repo,
  required KnowledgeEntryKind kind,
  required String id,
  required String title,
  required String ownerUserId,
}) async {
  await deleteKnowledgeEntry(
    context: context,
    ref: ref,
    repository: repo,
    kind: kind,
    id: id,
    title: title,
    ownerUserId: ownerUserId,
  );
}
