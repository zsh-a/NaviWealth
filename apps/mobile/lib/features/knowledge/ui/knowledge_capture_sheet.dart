/// Unified KnowledgeOS Capture sheet
/// (`docs/domains/knowledgeos-domain.md` §3 + §5 + §14).
///
/// One sheet, one textarea, one Save. Replaces the old Inbox-only
/// `_NewNoteSheet`. Default Auto mode lands as a `KnowledgeNote` first —
/// zero-latency, never blocks on AI. Users can also pick a concrete
/// target kind up front: Routine writes a structured row immediately;
/// Decision / Principle / Assumption / Concept / Experiment land as
/// candidate-tagged Notes for the typed writers. In Auto mode, after save,
/// the sheet awaits a single LLM round-trip via [captureClassifierProvider]
/// (LLM when a device profile is configured, deterministic heuristic
/// otherwise). When the classifier returns a non-Note kind the sheet swaps
/// its body for an inline "AI 建议升级" card with ✓ / ✗:
///
/// - ✓ promotes:
///   * `routine` → writes a [KnowledgeRoutine] + soft-deletes the
///     temp Note. RoutineDueAgent picks it up from the next tick.
///   * other kinds (decision / principle / assumption / concept /
///     experiment) → tags the Note with `kind:<x>_candidate` and a
///     possibly-extracted `scope:<...>` tag, same shape as
///     `queue_inbox_classification` produces. The Library typed
///     writers can later promote from the tagged Note.
/// - ✗ keeps the Note unchanged. Sheet closes.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/logging/providers.dart' show loggerProvider;
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/capture_classifier.dart';
import '../data/capture_kind.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

part 'knowledge_capture_views.dart';

Future<void> showKnowledgeCaptureSheet(BuildContext context, WidgetRef _) {
  return showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => const _KnowledgeCaptureSheet(),
  );
}

class _KnowledgeCaptureSheet extends ConsumerStatefulWidget {
  const _KnowledgeCaptureSheet();
  @override
  ConsumerState<_KnowledgeCaptureSheet> createState() =>
      _KnowledgeCaptureSheetState();
}

/// Sheet drives a small state machine. `composing` → user typing.
/// `saving` → upsertNote in flight (sync). `classifying` → note saved,
/// awaiting LLM classifier. `suggesting` → classifier returned an
/// upgrade, waiting for ✓ / ✗. `applying` → promote in flight.
enum _CaptureStage { composing, saving, classifying, suggesting, applying }

class _KnowledgeCaptureSheetState
    extends ConsumerState<_KnowledgeCaptureSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  _CaptureStage _stage = _CaptureStage.composing;
  CaptureKind? _manualKind;

  // Populated after save → classify().
  KnowledgeNote? _savedNote;
  CaptureClassification? _suggestion;

  @override
  void initState() {
    super.initState();
    _bodyCtrl.addListener(_onTextChange);
    _titleCtrl.addListener(_onTextChange);
  }

  void _onTextChange() {
    if (_stage == _CaptureStage.composing && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _stage == _CaptureStage.composing && _bodyCtrl.text.trim().isNotEmpty;

  Future<void> _saveAndClassify() async {
    if (!_canSave) return;
    final manualKind = _manualKind;
    setState(() => _stage = _CaptureStage.saving);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final note = KnowledgeNote(
        id: kKnowledgeUuid.v4(),
        title: _titleCtrl.text.trim(),
        bodyMd: _bodyCtrl.text,
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

      if (manualKind != null) {
        _savedNote = note;
        await _applyManualKind(note, manualKind);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // Classify against title + body together — the routine signal
      // sometimes lives in the title ("港卡活跃") and sometimes in the
      // body. The classifier provider returns the LLM impl when a
      // device profile is configured; otherwise the pure-Dart
      // heuristic. Either path is async + degrades to "note" on any
      // failure, so we never block the sheet.
      final text = <String>[
        if (_titleCtrl.text.trim().isNotEmpty) _titleCtrl.text.trim(),
        _bodyCtrl.text.trim(),
      ].join('\n');
      if (mounted) {
        setState(() {
          _savedNote = note;
          _stage = _CaptureStage.classifying;
        });
      }
      final classifier = ref.read(captureClassifierProvider);
      final logger = ref.read(loggerProvider);
      logger.d(
        '[capture-sheet] classify start impl=${classifier.runtimeType} '
        'text_len=${text.length}',
      );
      final classification = await classifier.classify(text: text);
      logger.i(
        '[capture-sheet] classify done kind=${classification.kind.wire} '
        'confidence=${classification.confidence.toStringAsFixed(2)} '
        'hasSuggestion=${classification.hasSuggestion} '
        '(isUpgrade=${classification.isUpgrade} hasPolish=${classification.hasPolish})',
      );
      if (!mounted) return;
      if (classification.hasSuggestion) {
        setState(() {
          _suggestion = classification;
          _stage = _CaptureStage.suggesting;
        });
      } else {
        logger.d(
          '[capture-sheet] no suggestion (Note kept as-is), closing sheet',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _stage = _CaptureStage.composing);
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).knowledgeCaptureSaveFailed('$e'),
        );
      }
    }
  }

  Future<void> _applyManualKind(KnowledgeNote note, CaptureKind kind) async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final title = note.title.trim();
    final statement = title.isNotEmpty
        ? knowledgeExcerpt(title, max: 60)
        : knowledgeExcerpt(note.bodyMd, max: 60);
    switch (kind) {
      case CaptureKind.routine:
        final stamp = await stamper.stamp();
        const intervalDays = 180;
        await repo.upsertRoutine(
          KnowledgeRoutine(
            id: kKnowledgeUuid.v4(),
            statement: statement,
            intervalDays: intervalDays,
            nextDueAt: stamp.now.add(const Duration(days: intervalDays)),
            scope: '*',
            status: RoutineStatus.active,
            createdAt: stamp.now,
            sync: SyncMeta(
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          ),
        );
        final tomb = await stamper.stamp();
        await repo.upsertNote(
          KnowledgeNote(
            id: note.id,
            title: note.title,
            bodyMd: note.bodyMd,
            sourceUrl: note.sourceUrl,
            tags: note.tags,
            projectTag: note.projectTag,
            createdAt: note.createdAt,
            sync: SyncMeta(
              ownerUserId: tomb.ownerUserId,
              updatedAt: tomb.now,
              updatedByDevice: tomb.deviceId,
              hlc: tomb.hlc,
              deletedAt: tomb.now,
            ),
          ),
        );
      case CaptureKind.decision:
      case CaptureKind.principle:
      case CaptureKind.assumption:
      case CaptureKind.concept:
      case CaptureKind.experiment:
        final candidateStamp = await stamper.stamp();
        final tags = note.tags.toSet()
          ..add('kind:${kind.wire}_candidate')
          ..add('source:manual_capture');
        await repo.upsertNote(
          KnowledgeNote(
            id: note.id,
            title: note.title,
            bodyMd: note.bodyMd,
            sourceUrl: note.sourceUrl,
            tags: tags.toList(growable: false),
            projectTag: note.projectTag,
            createdAt: note.createdAt,
            sync: SyncMeta(
              ownerUserId: candidateStamp.ownerUserId,
              updatedAt: candidateStamp.now,
              updatedByDevice: candidateStamp.deviceId,
              hlc: candidateStamp.hlc,
            ),
          ),
        );
      case CaptureKind.note:
        break;
    }
  }

  Future<void> _acceptUpgrade() async {
    final note = _savedNote;
    final suggestion = _suggestion;
    if (note == null || suggestion == null) return;
    setState(() => _stage = _CaptureStage.applying);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);

      // Resolved title / body that downstream writes use. When the LLM
      // produced a polish, that's the authoritative version going
      // forward — the raw input was always the temp lossy form.
      final resolvedTitle = suggestion.polishedTitle ?? note.title;
      final resolvedBody = suggestion.polishedBody ?? note.bodyMd;

      switch (suggestion.kind) {
        case CaptureKind.routine:
          // Routine promotion: write the structured row, then
          // soft-delete the temp Note. Polished title/body don't
          // travel onto a Routine (its surface is `statement`), but
          // we still tombstone with whatever the Note last held — the
          // user may have already saved a polish via a separate accept.
          final stamp = await stamper.stamp();
          final intervalDays = suggestion.intervalDays ?? 180;
          await repo.upsertRoutine(
            KnowledgeRoutine(
              id: kKnowledgeUuid.v4(),
              statement: suggestion.statement ?? resolvedTitle,
              intervalDays: intervalDays,
              nextDueAt: stamp.now.add(Duration(days: intervalDays)),
              scope: suggestion.scope ?? '*',
              status: RoutineStatus.active,
              createdAt: stamp.now,
              sync: SyncMeta(
                ownerUserId: stamp.ownerUserId,
                updatedAt: stamp.now,
                updatedByDevice: stamp.deviceId,
                hlc: stamp.hlc,
              ),
            ),
          );
          final tomb = await stamper.stamp();
          await repo.upsertNote(
            KnowledgeNote(
              id: note.id,
              title: note.title,
              bodyMd: note.bodyMd,
              sourceUrl: note.sourceUrl,
              tags: note.tags,
              projectTag: note.projectTag,
              createdAt: note.createdAt,
              sync: SyncMeta(
                ownerUserId: tomb.ownerUserId,
                updatedAt: tomb.now,
                updatedByDevice: tomb.deviceId,
                hlc: tomb.hlc,
                deletedAt: tomb.now,
              ),
            ),
          );
        case CaptureKind.decision:
        case CaptureKind.principle:
        case CaptureKind.assumption:
        case CaptureKind.concept:
        case CaptureKind.experiment:
          // Tag-only promotion: gain `kind:<x>_candidate` + optional
          // `scope:<...>` tags. If the LLM produced polished text we
          // write it in the same stamp — applying polish and category
          // tag is one logical "I accept the AI's read".
          final stamp = await stamper.stamp();
          final tagSet = note.tags.toSet();
          tagSet.add('kind:${suggestion.kind.wire}_candidate');
          if (suggestion.scope != null) {
            tagSet.add('scope:${suggestion.scope}');
          }
          await repo.upsertNote(
            KnowledgeNote(
              id: note.id,
              title: resolvedTitle,
              bodyMd: resolvedBody,
              sourceUrl: note.sourceUrl,
              tags: tagSet.toList(growable: false),
              projectTag: note.projectTag,
              createdAt: note.createdAt,
              sync: SyncMeta(
                ownerUserId: stamp.ownerUserId,
                updatedAt: stamp.now,
                updatedByDevice: stamp.deviceId,
                hlc: stamp.hlc,
              ),
            ),
          );
        case CaptureKind.note:
          // Polish-only path: classifier said "note" but produced a
          // rewrite worth showing. Apply just the polish in place.
          if (suggestion.hasPolish) {
            final stamp = await stamper.stamp();
            await repo.upsertNote(
              KnowledgeNote(
                id: note.id,
                title: resolvedTitle,
                bodyMd: resolvedBody,
                sourceUrl: note.sourceUrl,
                tags: note.tags,
                projectTag: note.projectTag,
                createdAt: note.createdAt,
                sync: SyncMeta(
                  ownerUserId: stamp.ownerUserId,
                  updatedAt: stamp.now,
                  updatedByDevice: stamp.deviceId,
                  hlc: stamp.hlc,
                ),
              ),
            );
          }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _stage = _CaptureStage.suggesting);
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).knowledgeCaptureApplyFailed('$e'),
        );
      }
    }
  }

  void _dismissSuggestion() {
    // ✗ → keep the saved Note as-is and close. The Note survived the
    // save step so dismissing just means the user agreed it's a Note.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = _stage;
    final isSuggestStage =
        stage == _CaptureStage.suggesting || stage == _CaptureStage.applying;
    final showSavedPreview =
        stage == _CaptureStage.classifying || isSuggestStage;
    final savedTitle = _savedNote?.title ?? _titleCtrl.text;
    final savedBody = _savedNote?.bodyMd ?? _bodyCtrl.text;
    return AppSheet(
      title: isSuggestStage
          ? l10n.knowledgeCaptureSuggestionTitle
          : stage == _CaptureStage.classifying
          ? l10n.knowledgeCaptureSavedClassifyingTitle
          : l10n.knowledgeCaptureTitle,
      subtitle: isSuggestStage
          ? l10n.knowledgeCaptureSuggestionSubtitle
          : stage == _CaptureStage.classifying
          ? l10n.knowledgeCaptureClassifyingSubtitle
          : l10n.knowledgeCaptureComposeSubtitle,
      footer: switch (stage) {
        _CaptureStage.composing || _CaptureStage.saving => AppSheetFooter(
          submitLabel: stage == _CaptureStage.saving
              ? l10n.knowledgeCaptureSaving
              : _manualKind == null
              ? l10n.knowledgeCaptureSave
              : l10n.knowledgeCaptureSaveTyped(
                  _captureKindShortLabel(l10n, _manualKind!),
                ),
          cancelLabel: l10n.knowledgeCaptureCancel,
          busy: !_canSave,
          onSubmit: () {
            _saveAndClassify();
          },
        ),
        _CaptureStage.suggesting || _CaptureStage.applying => AppSheetFooter(
          submitLabel: stage == _CaptureStage.applying
              ? l10n.knowledgeCaptureApplying
              : (_suggestion!.isUpgrade
                    ? l10n.knowledgeCaptureApplySuggestion
                    : l10n.knowledgeCaptureApplyPolish),
          cancelLabel: l10n.knowledgeCaptureKeepOriginal,
          busy: stage == _CaptureStage.applying,
          onSubmit: _acceptUpgrade,
          onCancel: _dismissSuggestion,
        ),
        _ => null,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: AppMotionPolicy.duration(context, Motion.medium),
            switchInCurve: Motion.standardDecelerate,
            switchOutCurve: Motion.standardAccelerate,
            transitionBuilder: _capturePreviewTransition,
            child: showSavedPreview
                ? _SavedCapturePreview(
                    key: const ValueKey<String>('saved-capture-preview'),
                    sectionTitle: stage == _CaptureStage.classifying
                        ? l10n.knowledgeCaptureSavedClassifyingTitle
                        : l10n.knowledgeCaptureSavedPreviewTitle,
                    promoted: isSuggestStage,
                    title: savedTitle,
                    body: savedBody,
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('no-saved-capture-preview'),
                  ),
          ),
          if (showSavedPreview) const SizedBox(height: AppSpacing.s12),
          AnimatedSwitcher(
            duration: AppMotionPolicy.duration(context, Motion.medium),
            switchInCurve: Motion.standardDecelerate,
            switchOutCurve: Motion.standardAccelerate,
            transitionBuilder: _captureStageTransition,
            child: switch (stage) {
              _CaptureStage.composing || _CaptureStage.saving => _ComposeBody(
                key: const ValueKey<String>('compose'),
                titleController: _titleCtrl,
                bodyController: _bodyCtrl,
                selectedKind: _manualKind,
                onKindChanged: (kind) => setState(() => _manualKind = kind),
              ),
              _CaptureStage.classifying => _ClassifyingBody(
                key: const ValueKey<String>('classifying'),
                onSkip: () {
                  // The Note is already persisted from `_saveAndClassify` →
                  // popping here just abandons the in-flight classifier.
                  // The `mounted` guard after the await drops whatever the
                  // LLM returns once it eventually lands.
                  if (mounted) Navigator.of(context).pop();
                },
              ),
              _CaptureStage.suggesting ||
              _CaptureStage.applying => _SuggestionBody(
                key: const ValueKey<String>('suggestion'),
                suggestion: _suggestion!,
                originalTitle: savedTitle,
                originalBody: savedBody,
                applying: stage == _CaptureStage.applying,
                onAccept: _acceptUpgrade,
                onDismiss: _dismissSuggestion,
              ),
            },
          ),
        ],
      ),
    );
  }
}
