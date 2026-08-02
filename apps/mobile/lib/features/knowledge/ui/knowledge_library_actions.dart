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
}) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(AppLocalizations.of(context).knowledgeLibraryDeleteTitle),
    body: Text(AppLocalizations.of(context).knowledgeLibraryDeleteBody(title)),
    confirmLabel: AppLocalizations.of(context).commonDelete,
    cancelLabel: AppLocalizations.of(context).commonCancel,
    destructive: true,
  );
  if (confirmed != true) return;

  try {
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    await repo.deleteEntry(
      kind: kind,
      id: id,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
        deletedAt: stamp.now,
      ),
    );
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).knowledgeDeletedToast,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).commonDeleteFailed,
      );
    }
  }
}
