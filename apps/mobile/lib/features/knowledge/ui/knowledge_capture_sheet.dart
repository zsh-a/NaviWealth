/// Unified KnowledgeOS Capture sheet
/// (`docs/domains/knowledgeos-domain.md` §3 + §5 + §14).
///
/// Capture always persists a [KnowledgeNote] and never exposes the object
/// taxonomy. When device AI is available, it can first produce an ephemeral
/// title + Markdown draft for user preview; the original remains available and
/// nothing is written until confirmation. Repository change scheduling still
/// runs classification, links, and contradiction work in the background.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_llm_client.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';
import 'knowledge_image_insert.dart';

part 'knowledge_capture_views.dart';

class _KnowledgeCaptureSaveResult {
  const _KnowledgeCaptureSaveResult({
    required this.saved,
    this.previous,
    required this.organized,
  });

  final KnowledgeNote saved;
  final KnowledgeNote? previous;
  final bool organized;
}

Future<void> showKnowledgeCaptureSheet(BuildContext context) async {
  final result = await showGuardedFormSheet<_KnowledgeCaptureSaveResult>(
    context: context,
    builder: (sheetContext, dirty) => _KnowledgeCaptureSheet(dirty: dirty),
  );
  if (result != null && context.mounted) {
    AppMessenger.show(
      context,
      ToastKind.success,
      AppLocalizations.of(context).knowledgeCaptureSavedToast,
    );
  }
}

/// Re-runs the capture organizer for an existing note without mutating it
/// until the user reviews and accepts the polished draft.
Future<void> showOrganizeKnowledgeNoteSheet(
  BuildContext context,
  KnowledgeNote note,
) async {
  final container = ProviderScope.containerOf(context);
  final result = await showGuardedFormSheet<_KnowledgeCaptureSaveResult>(
    context: context,
    builder: (sheetContext, dirty) => _KnowledgeCaptureSheet(
      dirty: dirty,
      initialNote: note,
      organizeOnOpen: true,
    ),
  );
  if (result != null && context.mounted) {
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.knowledgeCaptureSavedToast,
      actionLabel: result.organized && result.previous != null
          ? l10n.commonUndo
          : null,
      onAction: result.organized && result.previous != null
          ? () => unawaited(
              _undoOrganizedNote(
                context: context,
                container: container,
                previous: result.previous!,
                saved: result.saved,
              ),
            )
          : null,
    );
  }
}

Future<void> _undoOrganizedNote({
  required BuildContext context,
  required ProviderContainer container,
  required KnowledgeNote previous,
  required KnowledgeNote saved,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await container.read(knowledgeRepositoryProvider.future);
    final latest = await repo.findNote(
      ownerUserId: saved.sync.ownerUserId,
      id: saved.id,
    );
    if (latest == null ||
        latest.title != saved.title ||
        latest.bodyMd != saved.bodyMd) {
      throw StateError('The note changed after organization.');
    }
    final stamper = await container.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    await repo.upsertNote(
      KnowledgeNote(
        id: latest.id,
        title: previous.title,
        bodyMd: previous.bodyMd,
        sourceUrl: latest.sourceUrl,
        tags: latest.tags,
        projectTag: latest.projectTag,
        createdAt: latest.createdAt,
        promotedToKind: latest.promotedToKind,
        promotedToId: latest.promotedToId,
        promotedAt: latest.promotedAt,
        mergedIntoId: latest.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      ),
    );
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.commonUndoSucceeded);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonUndoFailed);
    }
  }
}

class _KnowledgeCaptureSheet extends ConsumerStatefulWidget {
  const _KnowledgeCaptureSheet({
    required this.dirty,
    this.initialNote,
    this.organizeOnOpen = false,
  });

  final FormDirtyController dirty;
  final KnowledgeNote? initialNote;
  final bool organizeOnOpen;
  @override
  ConsumerState<_KnowledgeCaptureSheet> createState() =>
      _KnowledgeCaptureSheetState();
}

enum _CaptureStage { composing, organizing, reviewing, saving }

class _KnowledgeCaptureSheetState
    extends ConsumerState<_KnowledgeCaptureSheet> {
  late final _titleCtrl = TextEditingController(
    text: widget.initialNote?.title ?? '',
  );
  late final _bodyCtrl = TextEditingController(
    text: widget.initialNote?.bodyMd ?? '',
  );
  final _bodyFocus = FocusNode();
  _CaptureStage _stage = _CaptureStage.composing;
  String? _originalTitle;
  String? _originalBody;

  @override
  void initState() {
    super.initState();
    _bodyCtrl.addListener(_onTextChange);
    _titleCtrl.addListener(_onTextChange);
    widget.dirty.bindTextControllers([_titleCtrl, _bodyCtrl]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.organizeOnOpen &&
          ref.read(knowledgeLlmProfileClientProvider) != null) {
        _organize();
      } else {
        _bodyFocus.requestFocus();
      }
    });
  }

  void _onTextChange() {
    if ((_stage == _CaptureStage.composing ||
            _stage == _CaptureStage.reviewing) &&
        mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _canSave =>
      (_stage == _CaptureStage.composing ||
          _stage == _CaptureStage.reviewing) &&
      _bodyCtrl.text.trim().isNotEmpty;

  bool get _canOrganize =>
      _stage == _CaptureStage.composing && _bodyCtrl.text.trim().isNotEmpty;

  Future<void> _organize() async {
    if (!_canOrganize) return;
    final originalTitle = _titleCtrl.text.trim();
    final originalBody = _bodyCtrl.text.trim();
    _originalTitle = originalTitle;
    _originalBody = originalBody;
    _bodyFocus.unfocus();
    setState(() => _stage = _CaptureStage.organizing);
    try {
      final result = await ref
          .read(captureClassifierProvider)
          .classify(
            text: jsonEncode(<String, Object?>{
              'original_title': originalTitle,
              'original_body_md': originalBody,
            }),
          );
      if (!mounted) return;
      final organizedBody = result.polishedBody?.trim();
      if (organizedBody == null ||
          organizedBody.isEmpty ||
          !_preservesKnowledgeAttachments(originalBody, organizedBody)) {
        throw const _CaptureOrganizationRejected();
      }
      final organizedTitle = result.polishedTitle?.trim();
      _replaceText(
        _titleCtrl,
        organizedTitle == null || organizedTitle.isEmpty
            ? _organizedFallbackTitle(organizedBody)
            : organizedTitle,
      );
      _replaceText(_bodyCtrl, organizedBody);
      setState(() => _stage = _CaptureStage.reviewing);
    } on Object {
      if (!mounted) return;
      setState(() => _stage = _CaptureStage.composing);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).knowledgeCaptureOrganizeFailed,
      );
    }
  }

  void _restoreOriginal() {
    _replaceText(_titleCtrl, _originalTitle ?? '');
    _replaceText(_bodyCtrl, _originalBody ?? '');
    _originalTitle = null;
    _originalBody = null;
    setState(() => _stage = _CaptureStage.composing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final previousStage = _stage;
    setState(() => _stage = _CaptureStage.saving);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final body = _bodyCtrl.text;
      final typedTitle = _titleCtrl.text.trim();
      final existing = widget.initialNote;
      final note = KnowledgeNote(
        id: existing?.id ?? kKnowledgeUuid.v4(),
        title: typedTitle.isEmpty ? _organizedFallbackTitle(body) : typedTitle,
        bodyMd: body,
        sourceUrl: existing?.sourceUrl,
        tags: existing?.tags ?? const <String>[],
        projectTag: existing?.projectTag,
        createdAt: existing?.createdAt ?? stamp.now,
        promotedToKind: existing?.promotedToKind,
        promotedToId: existing?.promotedToId,
        promotedAt: existing?.promotedAt,
        mergedIntoId: existing?.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertNote(note);
      widget.dirty.markPristine();
      if (mounted) {
        Navigator.of(context).pop(
          _KnowledgeCaptureSaveResult(
            saved: note,
            previous: existing,
            organized: previousStage == _CaptureStage.reviewing,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _stage = previousStage);
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (_stage == _CaptureStage.composing &&
        ref.read(knowledgeLlmProfileClientProvider) != null) {
      _organize();
    } else {
      _save();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = _stage;
    final aiAvailable = ref.watch(knowledgeLlmProfileClientProvider) != null;
    final title = switch (stage) {
      _CaptureStage.reviewing => l10n.knowledgeCapturePolishedVersionTitle,
      _ => l10n.knowledgeCaptureTitle,
    };
    final subtitle = switch (stage) {
      _CaptureStage.composing => l10n.knowledgeCaptureComposeSubtitle,
      _CaptureStage.organizing => l10n.knowledgeCaptureOrganizingSubtitle,
      _CaptureStage.reviewing => l10n.knowledgeCaptureOrganizedSubtitle,
      _CaptureStage.saving => null,
    };
    final footer = switch (stage) {
      _CaptureStage.composing => AppSheetFooter(
        submitLabel: aiAvailable
            ? l10n.knowledgeCaptureOrganizeAction
            : l10n.knowledgeCaptureSave,
        cancelLabel: l10n.knowledgeCaptureCancel,
        enabled: aiAvailable ? _canOrganize : _canSave,
        onSubmit: aiAvailable ? _organize : _save,
      ),
      _CaptureStage.organizing => AppSheetFooter(
        submitLabel: l10n.knowledgeCaptureOrganizing,
        cancelLabel: l10n.knowledgeCaptureCancel,
        busy: true,
        enabled: false,
        onSubmit: _organize,
      ),
      _CaptureStage.reviewing => AppSheetFooter(
        submitLabel: l10n.knowledgeCaptureSaveOrganized,
        cancelLabel: l10n.knowledgeCaptureKeepOriginal,
        enabled: _canSave,
        onCancel: _restoreOriginal,
        onSubmit: _save,
      ),
      _CaptureStage.saving => AppSheetFooter(
        submitLabel: l10n.commonSaving,
        cancelLabel: l10n.knowledgeCaptureCancel,
        busy: true,
        enabled: false,
        onSubmit: _save,
      ),
    };
    return Focus(
      onKeyEvent: _onKeyEvent,
      child: AppSheet(
        title: title,
        subtitle: subtitle,
        footer: footer,
        child: switch (stage) {
          _CaptureStage.composing => _ComposeBody(
            titleController: _titleCtrl,
            bodyController: _bodyCtrl,
            bodyFocusNode: _bodyFocus,
            aiAvailable: aiAvailable,
            onSaveOriginal: _canSave ? _save : null,
          ),
          _CaptureStage.organizing => const _CaptureProgressBody(),
          _CaptureStage.reviewing => _OrganizedReviewBody(
            titleController: _titleCtrl,
            bodyController: _bodyCtrl,
            originalTitle: _originalTitle ?? '',
            originalBody: _originalBody ?? '',
          ),
          _CaptureStage.saving => const _CaptureProgressBody(saving: true),
        },
      ),
    );
  }
}

void _replaceText(TextEditingController controller, String text) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

bool _preservesKnowledgeAttachments(String original, String organized) {
  final references = RegExp(
    r'attachment://[^\s)]+',
  ).allMatches(original).map((match) => match.group(0)!).toSet();
  return references.every(organized.contains);
}

String _organizedFallbackTitle(String body) {
  final firstLine = body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => body.trim())
      .replaceFirst(RegExp(r'^#{1,6}\s+'), '');
  return knowledgeExcerpt(firstLine);
}

class _CaptureOrganizationRejected implements Exception {
  const _CaptureOrganizationRejected();
}
