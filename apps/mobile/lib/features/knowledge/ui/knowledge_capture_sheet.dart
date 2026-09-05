import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/product/product_metrics.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_source_url.dart';
import 'widgets/knowledge_decision_options_editor.dart';
import 'widgets/knowledge_markdown_editor.dart';
import 'widgets/knowledge_tag_chips.dart';

enum _CaptureType { note, decision }

Future<void> showKnowledgeCaptureSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final type = await showAppSheet<_CaptureType>(
    context: context,
    title: l10n.knowledgeCaptureAction,
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: FLucideIcons.fileText,
          title: l10n.knowledgeNewNote,
          onPress: () => Navigator.pop(sheetContext, _CaptureType.note),
        ),
        AppActionSheetTile(
          icon: FLucideIcons.circleCheck,
          title: l10n.knowledgeNewDecision,
          onPress: () => Navigator.pop(sheetContext, _CaptureType.decision),
        ),
      ],
    ),
  );
  if (type == null) return;
  await Future<void>.delayed(Motion.medium);
  if (!context.mounted) return;
  if (type == _CaptureType.decision) {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(builder: (_) => const _DecisionCapturePage()),
    );
  } else {
    await showGuardedFormSheet<void>(
      context: context,
      builder: (_, dirty) => _KnowledgeCaptureSheet(dirty: dirty),
    );
  }
}

class _KnowledgeCaptureSheet extends ConsumerStatefulWidget {
  const _KnowledgeCaptureSheet({
    required this.dirty,
    this.fullPage = false,
    this.confirmLeave,
  });

  final bool fullPage;
  final Future<bool> Function()? confirmLeave;

  final FormDirtyController dirty;

  @override
  ConsumerState<_KnowledgeCaptureSheet> createState() =>
      _KnowledgeCaptureSheetState();
}

class _KnowledgeCaptureSheetState
    extends ConsumerState<_KnowledgeCaptureSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _source = TextEditingController();
  final _tags = TextEditingController();
  late final KnowledgeDecisionOptionsController _options;
  Timer? _sourceCheckDebounce;
  KnowledgeNote? _duplicateSource;
  var _sourceCheckSerial = 0;
  var _type = _CaptureType.note;
  var _saving = false;
  var _showMetadata = false;
  String? _error;

  bool get _canSave {
    final title = _title.text.trim();
    final body = _body.text.trim();
    return switch (_type) {
      _CaptureType.note => title.isNotEmpty || body.isNotEmpty,
      _CaptureType.decision => title.isNotEmpty && _options.isValid,
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.fullPage) _type = _CaptureType.decision;
    _options = KnowledgeDecisionOptionsController();
    _title.addListener(_onTextChanged);
    _body.addListener(_onTextChanged);
    _tags.addListener(_onTextChanged);
    _source.addListener(_onSourceChanged);
    _options.addListener(_onOptionsChanged);
    widget.dirty.bindTextControllers(<TextEditingController>[
      _title,
      _body,
      _source,
      _tags,
    ]);
  }

  @override
  void dispose() {
    _sourceCheckDebounce?.cancel();
    _title.removeListener(_onTextChanged);
    _body.removeListener(_onTextChanged);
    _tags.removeListener(_onTextChanged);
    _source.removeListener(_onSourceChanged);
    _options
      ..removeListener(_onOptionsChanged)
      ..dispose();
    _title.dispose();
    _body.dispose();
    _source.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final footer = AppSheetFooter(
      submitLabel: l10n.commonSave,
      cancelLabel: l10n.commonCancel,
      onSubmit: _save,
      enabled: _canSave,
      busy: _saving,
    );
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _title),
          enabled: !_saving,
          autofocus: true,
          textInputAction: TextInputAction.next,
          label: Text(
            _type == _CaptureType.note
                ? l10n.knowledgeCaptureTitleField
                : l10n.knowledgeDecisionQuestionLabel,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (_type == _CaptureType.decision) ...[
          KnowledgeDecisionOptionsEditor(
            controller: _options,
            keyPrefix: 'knowledge-capture-option',
            enabled: !_saving,
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        KnowledgeMarkdownEditor(
          controller: _body,
          minLines: 4,
          maxLines: 10,
          enabled: !_saving,
          label: _type == _CaptureType.note
              ? l10n.knowledgeCaptureBodyField
              : l10n.knowledgeWriterRationaleMarkdownLabel,
        ),
        if (_type == _CaptureType.note) ...[
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => setState(() => _showMetadata = !_showMetadata),
            child: Text(l10n.knowledgeCaptureMetadata),
          ),
        ],
        if (_type == _CaptureType.note)
          AnimatedSizeFade(
            visible: _showMetadata,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.s12),
                FTextField(
                  key: const ValueKey('knowledge-capture-source-url'),
                  control: FTextFieldControl.managed(controller: _source),
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  label: Text(l10n.knowledgeNoteSourceUrlLabel),
                ),
                if (_source.text.trim().isNotEmpty &&
                    normalizeKnowledgeSourceUrl(_source.text) == null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppStatusBanner(
                    kind: AppStatusKind.error,
                    compact: true,
                    message: l10n.knowledgeSourceInvalid,
                  ),
                ],
                if (_duplicateSource != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppStatusBanner(
                    key: const Key('knowledge-duplicate-source-warning'),
                    kind: AppStatusKind.warning,
                    compact: true,
                    message: l10n.knowledgeSourceDuplicateTitle,
                    details: l10n.knowledgeSourceDuplicateBody(
                      _duplicateSource!.title.isEmpty
                          ? l10n.knowledgeUntitled
                          : _duplicateSource!.title,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s12),
                FTextField(
                  key: const ValueKey('knowledge-capture-tags'),
                  control: FTextFieldControl.managed(controller: _tags),
                  enabled: !_saving,
                  label: Text(l10n.knowledgeNoteTagsLabel),
                  hint: l10n.knowledgeNoteTagsHint,
                ),
                if (parseKnowledgeTags(_tags.text) case final tagPreview
                    when tagPreview.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  KnowledgeTagChips(
                    tags: tagPreview,
                    keyPrefix: 'knowledge-capture-tag',
                  ),
                ],
              ],
            ),
          ),
        if (_error case final message?) ...[
          const SizedBox(height: AppSpacing.s10),
          AppStatusBanner(
            kind: AppStatusKind.error,
            compact: true,
            message: message,
          ),
        ],
      ],
    );
    if (widget.fullPage) {
      return AppFormPageScaffold(
        title: Text(l10n.knowledgeNewDecision),
        confirmLeave: widget.confirmLeave,
        child: AppFormScaffoldBody(
          action: footer,
          onSubmit: _canSave && !_saving ? _save : null,
          children: [fields],
        ),
      );
    }
    return AppSheet(
      title: l10n.knowledgeCaptureTitle,
      footer: footer,
      child: fields,
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    final sourceUrl = normalizeKnowledgeSourceUrl(_source.text);
    if (!_canSave) {
      setState(() {
        _error = _type == _CaptureType.decision
            ? AppLocalizations.of(context).knowledgeDecisionOptionsInvalid
            : AppLocalizations.of(context).knowledgeNoteSaveRequirement;
      });
      return;
    }
    if (_type == _CaptureType.note &&
        _source.text.trim().isNotEmpty &&
        sourceUrl == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final value = await stamper.stamp();
      final sync = SyncMeta(
        ownerUserId: value.ownerUserId,
        updatedAt: value.now,
        updatedByDevice: value.deviceId,
        hlc: value.hlc,
      );
      if (_type == _CaptureType.note) {
        await repository.upsertNote(
          KnowledgeNote(
            id: kKnowledgeUuid.v4(),
            title: title,
            bodyMd: body,
            sourceUrl: sourceUrl,
            tags: _tags.text
                .split(RegExp(r'[,，\s]+'))
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false),
            createdAt: value.now,
            sync: sync,
          ),
        );
      } else {
        await repository.upsertDecision(
          KnowledgeDecision(
            id: kKnowledgeUuid.v4(),
            question: title,
            options: _options.options,
            selectedLabel: _options.selectedLabel,
            rationaleMd: body,
            status: DecisionStatus.active,
            decidedAt: value.now,
            sync: sync,
          ),
        );
        await recordProductMetric(
          () => ref.read(productMetricsProvider.notifier),
          ProductFunnelEvent.knowledgeDecisionCreated,
          success: true,
        );
      }
      ref.invalidate(knowledgeNotesProvider);
      ref.invalidate(knowledgeDecisionsProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'capture knowledge',
        );
      });
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onOptionsChanged() {
    widget.dirty.markDirty();
    if (mounted) setState(() => _error = null);
  }

  void _onTextChanged() {
    if (mounted) setState(() => _error = null);
  }

  void _onSourceChanged() {
    _sourceCheckDebounce?.cancel();
    final serial = ++_sourceCheckSerial;
    if (mounted) {
      setState(() => _duplicateSource = null);
    }
    final sourceUrl = normalizeKnowledgeSourceUrl(_source.text);
    if (sourceUrl == null) return;
    _sourceCheckDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_checkDuplicateSource(sourceUrl, serial)),
    );
  }

  Future<void> _checkDuplicateSource(String sourceUrl, int serial) async {
    KnowledgeNote? duplicate;
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final ownerUserId = await ref.read(knowledgeOwnerUserIdProvider.future);
      duplicate = await repository.findNoteBySourceUrl(
        ownerUserId: ownerUserId,
        sourceUrl: sourceUrl,
      );
    } on Object {
      duplicate = null;
    }
    if (!mounted ||
        serial != _sourceCheckSerial ||
        normalizeKnowledgeSourceUrl(_source.text) != sourceUrl) {
      return;
    }
    setState(() => _duplicateSource = duplicate);
  }
}

class _DecisionCapturePage extends ConsumerStatefulWidget {
  const _DecisionCapturePage();

  @override
  ConsumerState<_DecisionCapturePage> createState() =>
      _DecisionCapturePageState();
}

class _DecisionCapturePageState extends ConsumerState<_DecisionCapturePage>
    with FormDirtyGuard<_DecisionCapturePage> {
  @override
  String get leaveFallback => '/knowledge';

  @override
  Widget build(BuildContext context) => guardedScope(
    child: _KnowledgeCaptureSheet(
      dirty: dirty,
      fullPage: true,
      confirmLeave: handleBackIntent,
    ),
  );
}
