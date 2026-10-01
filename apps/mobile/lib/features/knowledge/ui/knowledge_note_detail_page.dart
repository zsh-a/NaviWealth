import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/forms/form_submission.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_rewrite_client.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_source_url.dart';
import 'knowledge_capture_sheet.dart';
import 'knowledge_rewrite_sheet.dart';
import 'widgets/knowledge_markdown_editor.dart';
import 'widgets/knowledge_relations_section.dart';
import 'widgets/knowledge_rewrite_action.dart';
import 'widgets/knowledge_source_link.dart';
import 'widgets/knowledge_tag_chips.dart';
import 'widgets/knowledge_tag_input.dart';

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
    return value.when(
      loading: () => ObjectDetailScaffold(
        title: l10n.knowledgeSegmentNotes,
        child: kDefaultLoading,
      ),
      error: (error, stackTrace) => ObjectDetailScaffold(
        title: l10n.knowledgeSegmentNotes,
        child: kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () => ref.invalidate(_noteProvider(noteId)),
        ),
      ),
      data: (note) => note == null
          ? ObjectDetailScaffold(
              title: l10n.knowledgeSegmentNotes,
              child: Center(child: Text(l10n.knowledgeObjectNotFound)),
            )
          : _NoteEditor(key: ValueKey(note.sync.hlc), note: note),
    );
  }
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({super.key, required this.note});

  final KnowledgeNote note;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor>
    with FormDirtyGuard<_NoteEditor>, FormSubmission<_NoteEditor> {
  @override
  String get leaveFallback => KnowledgeRoutes.library;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _source;
  late final TextEditingController _tags;
  final _formKey = GlobalKey<FormState>();
  var _saving = false;

  /// Detail pages open in read mode; the form stays behind this toggle.
  var _editing = false;
  var _showMetadata = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.bodyMd);
    _source = TextEditingController(text: widget.note.sourceUrl);
    _tags = TextEditingController(text: widget.note.tags.join(', '));
    dirty.bindTextControllers(<TextEditingController>[
      _title,
      _body,
      _source,
      _tags,
    ]);
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
    return guardedScope(
      child: ObjectDetailScaffold(
        title: l10n.knowledgeSegmentNotes,
        confirmLeave: handleBackIntent,
        resizeToAvoidBottomInset: !_editing,
        actions: [
          AppHeaderAction(
            key: const Key('knowledge-note-edit-toggle'),
            semanticsLabel: _editing
                ? l10n.knowledgeViewAction
                : l10n.knowledgeEditAction,
            icon: Icon(_editing ? FLucideIcons.eye : FLucideIcons.pencil),
            onPress: _saving ? null : _toggleMode,
          ),
          AppAdaptiveActionMenu(
            title: l10n.shellMoreActions,
            actions: [
              AppAdaptiveAction(
                icon: FLucideIcons.trash2,
                title: l10n.commonDelete,
                destructive: true,
                onPress: _delete,
              ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => Focus(
              focusNode: focusNode,
              child: AppIconButton(
                icon: FLucideIcons.ellipsis,
                tooltip: l10n.shellMoreActions,
                onPress: _saving ? null : openMenu,
              ),
            ),
          ),
        ],
        child: AnimatedBuilder(
          animation: dirty,
          builder: (context, _) =>
              _editing ? _buildEditForm(context) : _buildReadView(context),
        ),
      ),
    );
  }

  Widget _buildReadView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = widget.note;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final created = DateFormat.yMMMd(locale).format(note.createdAt.toLocal());
    final updated = DateFormat.yMMMd(locale)
        .format(note.sync.updatedAt.toLocal());
    final sourceUrl = note.sourceUrl;
    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.narrow,
      padding: EdgeInsets.zero,
      expandSinglePrimary: true,
      primary: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          Text(
            note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
            style: context.strongHeadlineStyle,
          ),
          if (note.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            KnowledgeTagChips(
              tags: note.tags,
              keyPrefix: 'knowledge-note-tag',
              onTagPressed: GoRouter.maybeOf(context) == null
                  ? null
                  : (tag) => context.go(
                      Uri(
                        path: KnowledgeRoutes.library,
                        queryParameters: {
                          'scope': 'notes',
                          'tag': tag,
                          'selected': 'note:${note.id}',
                        },
                      ).toString(),
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          if (note.bodyMd.trim().isEmpty)
            Text(l10n.knowledgeNoteEmptyBody, style: context.bodyCaptionStyle)
          else
            AiMarkdown(text: note.bodyMd),
          if (sourceUrl != null) ...[
            const SizedBox(height: AppSpacing.s12),
            KnowledgeSourceLink(sourceUrl: sourceUrl),
          ],
          const SizedBox(height: AppSpacing.s20),
          AppMetadataStrip(
            children: [
              AppMetadataItem(
                label: l10n.knowledgeCreatedLabel,
                value: created,
              ),
              AppMetadataItem(
                label: l10n.knowledgeUpdatedLabel,
                value: updated,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s20),
          KnowledgeRelationsSection(
            subjectKind: KnowledgeEntryKind.note,
            subjectId: widget.note.id,
            subjectText: KnowledgeSearchDocument.fromNote(widget.note)
                .searchText,
            onCreateDecision: _createDecision,
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        onSubmit: dirty.isDirty && !_saving ? _save : null,
        action: AppSheetFooter(
          submitLabel: l10n.commonSave,
          cancelLabel: l10n.commonCancel,
          enabled: dirty.isDirty,
          busy: _saving,
          onSubmit: _save,
          onCancel: _toggleMode,
        ),
        children: [
          FTextFormField(
            key: const Key('knowledge-note-title'),
            control: FTextFieldControl.managed(controller: _title),
            enabled: !_saving,
            label: Text(l10n.knowledgeCaptureTitleField),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) && _body.text.trim().isEmpty
                ? l10n.knowledgeNoteSaveRequirement
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeMarkdownEditor(
            controller: _body,
            editorKey: const Key('knowledge-note-body'),
            label: l10n.knowledgeCaptureBodyField,
            minLines: 8,
            enabled: !_saving,
          ),
          const SizedBox(height: AppSpacing.s8),
          KnowledgeRewriteAction(enabled: !_saving, onRewrite: _rewrite),
          const SizedBox(height: AppSpacing.s12),
          AppRevealControl(
            expanded: _showMetadata,
            collapsedLabel: l10n.knowledgeCaptureMetadata,
            expandedLabel: l10n.knowledgeCaptureMetadata,
            enabled: !_saving,
            onToggle: () => setState(() => _showMetadata = !_showMetadata),
          ),
          if (_showMetadata) ...[
            KnowledgeTagInput(controller: _tags, enabled: !_saving),
            const SizedBox(height: AppSpacing.s12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _source,
              builder: (context, value, _) {
                final sourceUrl = normalizeKnowledgeSourceUrl(value.text);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sourceUrl != null) ...[
                      KnowledgeSourceLink(sourceUrl: sourceUrl),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: _source),
                      enabled: !_saving,
                      keyboardType: TextInputType.url,
                      label: Text(l10n.knowledgeNoteSourceUrlLabel),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        return normalizeKnowledgeSourceUrl(text) == null
                            ? l10n.knowledgeSourceInvalid
                            : null;
                      },
                    ),
                  ],
                );
              },
            ),
          ],
          if (submissionFailureMessage case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(message: message, kind: AppStatusKind.error),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleMode() async {
    if (_editing) {
      final discard = await confirmDiscardIfDirty(context, dirty);
      if (!discard || !mounted) return;
      _resetFields();
    }
    setState(() => _editing = !_editing);
  }

  void _resetFields() {
    _title.text = widget.note.title;
    _body.text = widget.note.bodyMd;
    _source.text = widget.note.sourceUrl ?? '';
    _tags.text = widget.note.tags.join(', ');
    dirty.markPristine();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_source.text.trim().isNotEmpty &&
        normalizeKnowledgeSourceUrl(_source.text) == null) {
      setState(() => _showMetadata = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final sourceUrl = normalizeKnowledgeSourceUrl(_source.text);
    await submitForm<void>(
      dirty: dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () async {
        final repository = await ref.read(knowledgeRepositoryProvider.future);
        final stamper = await ref.read(mutationStamperProvider.future);
        final value = await stamper.stamp();
        await repository.upsertNote(
          KnowledgeNote(
            id: widget.note.id,
            title: _title.text.trim(),
            bodyMd: _body.text.trim(),
            sourceUrl: sourceUrl,
            tags: parseKnowledgeTags(_tags.text),
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
      },
      leave: () {
        ref.invalidate(_noteProvider(widget.note.id));
        ref.invalidate(knowledgeNotesProvider);
      },
      failureMessage: (error) => userSafeErrorMessage(
        context,
        error,
        operation: 'save knowledge note',
      ),
      successMessage: l10n.commonSaved,
      tag: 'knowledge-note-edit',
    );
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

  Future<void> _createDecision() async {
    FocusScope.of(context).unfocus();
    final decisionId = await showKnowledgeDecisionCapturePage(
      context,
      sourceNote: widget.note,
    );
    if (!mounted || decisionId == null) return;
    await context.push<void>(KnowledgeRoutes.decision(decisionId));
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.knowledgeNoteDeleteConfirmTitle),
      body: Text(l10n.knowledgeDeleteConfirmBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    dirty.busy = true;
    try {
      final service = await ref.read(knowledgeDeletionServiceProvider.future);
      await service.delete(kind: KnowledgeEntryKind.note, id: widget.note.id);
      ref.invalidate(knowledgeNotesProvider);
      dirty.markPristine();
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.commonDeleted);
        popOrGo(context, fallback: KnowledgeRoutes.library);
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'delete knowledge note',
        ),
      );
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }
}
