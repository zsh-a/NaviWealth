import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/visual/ai_pill.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_rewrite_client.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_rewrite_sheet.dart';
import 'widgets/knowledge_markdown_editor.dart';

final _noteProvider = FutureProvider.autoDispose.family<KnowledgeNote?, String>(
  (ref, id) async {
    final repository = await ref.watch(knowledgeRepositoryProvider.future);
    final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
    return repository.findNote(ownerUserId: owner, id: id);
  },
);

class KnowledgeNoteDetailPage extends ConsumerWidget {
  const KnowledgeNoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(_noteProvider(noteId));
    return ObjectDetailScaffold(
      title: l10n.knowledgeSegmentNotes,
      child: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.commonLoadFailed)),
        data: (note) => note == null
            ? Center(child: Text(l10n.knowledgeObjectNotFound))
            : _NoteEditor(key: ValueKey(note.sync.hlc), note: note),
      ),
    );
  }
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({super.key, required this.note});

  final KnowledgeNote note;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _source;
  late final TextEditingController _tags;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.bodyMd);
    _source = TextEditingController(text: widget.note.sourceUrl);
    _tags = TextEditingController(text: widget.note.tags.join(', '));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _source.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: l10n.knowledgeCaptureTitleField,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        KnowledgeMarkdownEditor(
          controller: _body,
          label: l10n.knowledgeCaptureBodyField,
          minLines: 8,
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.s8),
        Align(
          alignment: Alignment.centerLeft,
          child: AiPill(
            leading: const Icon(FLucideIcons.pencil, size: AppIconSizes.xs),
            label: l10n.knowledgeRewriteAction,
            onTap: _saving ? null : _rewrite,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        TextField(
          controller: _tags,
          decoration: InputDecoration(labelText: l10n.knowledgeNoteTagsLabel),
        ),
        const SizedBox(height: AppSpacing.s12),
        TextField(
          controller: _source,
          decoration: InputDecoration(
            labelText: l10n.knowledgeNoteSourceUrlLabel,
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.commonSaving : l10n.commonSave),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextButton(
          onPressed: _saving ? null : _delete,
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final value = await stamper.stamp();
      await repository.upsertNote(
        KnowledgeNote(
          id: widget.note.id,
          title: _title.text.trim(),
          bodyMd: _body.text.trim(),
          sourceUrl: _source.text.trim().isEmpty ? null : _source.text.trim(),
          tags: _tags.text
              .split(RegExp(r'[,，\s]+'))
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false),
          createdAt: widget.note.createdAt,
          mergedIntoId: widget.note.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: value.ownerUserId,
            updatedAt: value.now,
            updatedByDevice: value.deviceId,
            hlc: value.hlc,
          ),
        ),
      );
      ref.invalidate(_noteProvider(widget.note.id));
      ref.invalidate(knowledgeNotesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rewrite() async {
    FocusScope.of(context).unfocus();
    final draft = await showKnowledgeRewriteSheet(
      context: context,
      kind: KnowledgeRewriteKind.note,
      objectId: widget.note.id,
      heading: _title.text,
      content: _body.text,
    );
    if (!mounted || draft == null) return;
    setState(() {
      _title.text = draft.heading;
      _body.text = draft.content;
    });
  }

  Future<void> _delete() async {
    final service = await ref.read(knowledgeDeletionServiceProvider.future);
    await service.delete(kind: KnowledgeEntryKind.note, id: widget.note.id);
    ref.invalidate(knowledgeNotesProvider);
    if (mounted) context.pop();
  }
}
