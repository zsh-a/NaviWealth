/// KnowledgeOS Inbox tab (`docs/knowledgeos-domain.md` §5).
///
/// MVP: a Forui-only surface with a "New note" affordance. Notes are
/// markdown — input via [FTextField], preview via [AiMarkdown] (the
/// codebase's tuned renderer, see `lib/core/ai/visual/ai_markdown.dart`).
/// No 3rd-party markdown editor library: §8 反目标 bans block / WYSIWYG
/// editors ("AI Notion" trap) and the existing renderer covers display.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_segmented_row.dart';

const _kUuid = Uuid();

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      header: const FHeader.nested(title: Text('Inbox · KnowledgeOS')),
      childPad: false,
      child: Stack(
        children: [
          const Positioned.fill(child: _InboxBody()),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: FButton(
              prefix: const Icon(FLucideIcons.plus, size: 16),
              onPress: () => _showNewNoteSheet(context, ref),
              child: const Text('New note'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxBody extends ConsumerWidget {
  const _InboxBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(knowledgeRepositoryProvider);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const _Centered(child: FProgress());
        final owner = ownerSnap.data!;
        return repoAsync.when(
          loading: () => const _Centered(child: FProgress()),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (repo) {
            return StreamBuilder<List<KnowledgeNote>>(
              stream: repo.watchNotes(ownerUserId: owner, limit: 50),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <KnowledgeNote>[];
                if (notes.isEmpty) return const _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s8,
                    AppSpacing.s16,
                    // Bottom padding leaves room for the floating FAB.
                    AppSpacing.s64,
                  ),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s8),
                  itemBuilder: (context, i) => _NoteCard(note: notes[i]),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? '(untitled)' : note.title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
          ),
          if (note.bodyMd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              note.bodyMd.length > 200
                  ? '${note.bodyMd.substring(0, 200)}…'
                  : note.bodyMd,
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FLucideIcons.inbox, size: 48, color: colors.mutedForeground),
            const SizedBox(height: AppSpacing.s8),
            Text('收件箱空空如也', style: typography.lg),
            const SizedBox(height: AppSpacing.s4),
            Text(
              '点击右下角 + 写一条第一性思考、网页摘录或灵感片段。',
              textAlign: TextAlign.center,
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Text('Inbox 加载失败:$message'),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}

Future<void> _showNewNoteSheet(BuildContext context, WidgetRef ref) {
  return showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => _NewNoteSheet(ref: ref),
  );
}

enum _NoteEditMode { edit, preview }

class _NewNoteSheet extends StatefulWidget {
  const _NewNoteSheet({required this.ref});
  final WidgetRef ref;

  @override
  State<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends State<_NewNoteSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  _NoteEditMode _mode = _NoteEditMode.edit;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(
        knowledgeRepositoryProvider.future,
      );
      final stamper = await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final note = KnowledgeNote(
        id: _kUuid.v4(),
        title: _titleController.text.trim(),
        bodyMd: _bodyController.text,
        tags: const <String>[],
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertNote(note);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return AppSheet(
      title: 'New note',
      footer: AppSheetFooter(
        submitLabel: _saving ? 'Saving…' : 'Save',
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _titleController),
            label: const Text('Title'),
            hint: 'Note title',
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSegmentedRow<_NoteEditMode>(
            options: _NoteEditMode.values,
            value: _mode,
            labelOf: (m) => switch (m) {
              _NoteEditMode.edit => 'Edit',
              _NoteEditMode.preview => 'Preview',
            },
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_mode == _NoteEditMode.edit)
            FTextField(
              control: FTextFieldControl.managed(controller: _bodyController),
              label: const Text('Body (Markdown)'),
              hint: 'Free-form markdown — `#` 标题 / `**bold**` / 列表 等',
              maxLines: 8,
              minLines: 4,
            )
          else
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.border),
              ),
              child: _bodyController.text.trim().isEmpty
                  ? Text(
                      'Nothing to preview — switch back to Edit and type.',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    )
                  : AiMarkdown(text: _bodyController.text),
            ),
        ],
      ),
    );
  }
}
