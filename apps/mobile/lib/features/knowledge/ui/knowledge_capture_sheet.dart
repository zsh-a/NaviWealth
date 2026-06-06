/// Unified KnowledgeOS Capture sheet
/// (`docs/knowledgeos-domain.md` §3 + §5 + §14).
///
/// One sheet, one textarea, one Save. Replaces the old Inbox-only
/// `_NewNoteSheet`. The capture always lands as a `KnowledgeNote` —
/// zero-latency, never blocks on AI. After save, the sheet awaits a
/// single LLM round-trip via [captureClassifierProvider] (LLM when a
/// device profile is configured, deterministic heuristic otherwise).
/// When the classifier returns a non-Note kind the sheet swaps its
/// body for an inline "AI 建议升级" card with ✓ / ✗:
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

Future<void> showKnowledgeCaptureSheet(BuildContext context, WidgetRef ref) {
  return showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => _KnowledgeCaptureSheet(ref: ref),
  );
}

class _KnowledgeCaptureSheet extends StatefulWidget {
  const _KnowledgeCaptureSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_KnowledgeCaptureSheet> createState() => _KnowledgeCaptureSheetState();
}

/// Sheet drives a small state machine. `composing` → user typing.
/// `saving` → upsertNote in flight (sync). `classifying` → note saved,
/// awaiting LLM classifier. `suggesting` → classifier returned an
/// upgrade, waiting for ✓ / ✗. `applying` → promote in flight.
enum _CaptureStage { composing, saving, classifying, suggesting, applying }

class _KnowledgeCaptureSheetState extends State<_KnowledgeCaptureSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  _CaptureStage _stage = _CaptureStage.composing;

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
    setState(() => _stage = _CaptureStage.saving);
    try {
      final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper = await widget.ref.read(mutationStamperProvider.future);
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
      final classifier = widget.ref.read(captureClassifierProvider);
      final logger = widget.ref.read(loggerProvider);
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

  Future<void> _acceptUpgrade() async {
    final note = _savedNote;
    final suggestion = _suggestion;
    if (note == null || suggestion == null) return;
    setState(() => _stage = _CaptureStage.applying);
    try {
      final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper = await widget.ref.read(mutationStamperProvider.future);

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
      footer: stage == _CaptureStage.composing || stage == _CaptureStage.saving
          ? AppSheetFooter(
              submitLabel: stage == _CaptureStage.saving
                  ? l10n.knowledgeCaptureSaving
                  : l10n.knowledgeCaptureSave,
              cancelLabel: l10n.knowledgeCaptureCancel,
              busy: !_canSave,
              onSubmit: () {
                _saveAndClassify();
              },
            )
          : null,
      child: switch (stage) {
        _CaptureStage.composing || _CaptureStage.saving => _ComposeBody(
          titleController: _titleCtrl,
          bodyController: _bodyCtrl,
        ),
        _CaptureStage.classifying => _ClassifyingBody(
          onSkip: () {
            // The Note is already persisted from `_saveAndClassify` →
            // popping here just abandons the in-flight classifier.
            // The `mounted` guard after the await drops whatever the
            // LLM returns once it eventually lands.
            if (mounted) Navigator.of(context).pop();
          },
        ),
        _CaptureStage.suggesting || _CaptureStage.applying => _SuggestionBody(
          suggestion: _suggestion!,
          originalTitle: _savedNote?.title ?? '',
          originalBody: _savedNote?.bodyMd ?? '',
          applying: stage == _CaptureStage.applying,
          onAccept: _acceptUpgrade,
          onDismiss: _dismissSuggestion,
        ),
      },
    );
  }
}

class _ClassifyingBody extends StatelessWidget {
  const _ClassifyingBody({required this.onSkip});

  /// Bail out of the wait — the Note is already saved, the in-flight
  /// classifier becomes an orphan and its eventual result is dropped
  /// by the sheet's `mounted` guard. Useful for slow thinking models
  /// (mimo / Claude extended thinking) where the round-trip can take
  /// 20-30 s.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    // FProgress is a linear track that wants `constraints.maxWidth` from
    // its parent (no intrinsic horizontal size). Putting it in a Row
    // would hand it unbounded width → layout fails inside
    // AppSheet's AnimatedSize. Column with `stretch` keeps width
    // bounded by the sheet.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FProgress(),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.knowledgeCaptureClassifyingBody,
            textAlign: TextAlign.center,
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.center,
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: onSkip,
              child: Text(l10n.knowledgeCaptureSkipClassification),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    required this.titleController,
    required this.bodyController,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(AppLocalizations.of(context).knowledgeCaptureTitleField),
          hint: AppLocalizations.of(context).knowledgeCaptureTitleHint,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          label: Text(AppLocalizations.of(context).knowledgeCaptureBodyField),
          hint: AppLocalizations.of(context).knowledgeCaptureBodyHint,
          minLines: 4,
          maxLines: 8,
        ),
      ],
    );
  }
}

class _SuggestionBody extends StatelessWidget {
  const _SuggestionBody({
    required this.suggestion,
    required this.originalTitle,
    required this.originalBody,
    required this.applying,
    required this.onAccept,
    required this.onDismiss,
  });
  final CaptureClassification suggestion;
  final String originalTitle;
  final String originalBody;
  final bool applying;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final acceptLabel = applying
        ? l10n.knowledgeCaptureApplying
        : (suggestion.isUpgrade
              ? l10n.knowledgeCaptureApplySuggestion
              : l10n.knowledgeCaptureApplyPolish);
    final dismissLabel = l10n.knowledgeCaptureKeepOriginal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestion.hasPolish)
          _PolishPanel(
            suggestion: suggestion,
            originalTitle: originalTitle,
            originalBody: originalBody,
          ),
        if (suggestion.hasPolish && suggestion.isUpgrade)
          const SizedBox(height: AppSpacing.s8),
        if (suggestion.isUpgrade) _UpgradePanel(suggestion: suggestion),
        if (!suggestion.isUpgrade && suggestion.hasPolish)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Text(
              l10n.knowledgeCaptureNotePolishOnly(suggestion.reasonZh),
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: applying ? null : onDismiss,
              child: Text(dismissLabel),
            ),
            const SizedBox(width: AppSpacing.s8),
            FButton(
              onPress: applying ? null : onAccept,
              child: Text(acceptLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _PolishPanel extends StatelessWidget {
  const _PolishPanel({
    required this.suggestion,
    required this.originalTitle,
    required this.originalBody,
  });
  final CaptureClassification suggestion;
  final String originalTitle;
  final String originalBody;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final titleChanged =
        suggestion.polishedTitle != null &&
        suggestion.polishedTitle != originalTitle;
    final bodyChanged =
        suggestion.polishedBody != null &&
        suggestion.polishedBody != originalBody;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.wand,
                size: AppIconSizes.xs,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                l10n.knowledgeCapturePolishedVersionTitle,
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (titleChanged) ...[
            _DiffRow(
              label: l10n.knowledgeCaptureTitleDiffLabel,
              before: originalTitle.isEmpty
                  ? l10n.knowledgeCaptureEmptyValue
                  : originalTitle,
              after: suggestion.polishedTitle!,
            ),
            if (bodyChanged) const SizedBox(height: AppSpacing.s8),
          ],
          if (bodyChanged)
            _DiffRow(
              label: l10n.knowledgeCaptureBodyDiffLabel,
              before: originalBody.isEmpty
                  ? l10n.knowledgeCaptureEmptyValue
                  : originalBody,
              after: suggestion.polishedBody!,
            ),
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.before,
    required this.after,
  });
  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: typography.xs.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          l10n.knowledgeCaptureOriginalDiffValue(knowledgeExcerpt(before)),
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          '→ ${knowledgeExcerpt(after)}',
          style: typography.sm.copyWith(color: colors.primary),
        ),
      ],
    );
  }
}

class _UpgradePanel extends StatelessWidget {
  const _UpgradePanel({required this.suggestion});
  final CaptureClassification suggestion;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final headline = switch (suggestion.kind) {
      CaptureKind.routine => l10n.knowledgeCaptureKindRoutineDescription,
      CaptureKind.decision => l10n.knowledgeCaptureKindDecisionDescription,
      CaptureKind.assumption => l10n.knowledgeCaptureKindAssumptionDescription,
      CaptureKind.principle => l10n.knowledgeCaptureKindPrincipleDescription,
      CaptureKind.concept => l10n.knowledgeCaptureKindConceptDescription,
      CaptureKind.experiment => l10n.knowledgeCaptureKindExperimentDescription,
      CaptureKind.note => l10n.knowledgeCaptureKindNoteDescription,
    };
    final detail = switch (suggestion.kind) {
      CaptureKind.routine =>
        '${l10n.knowledgeCaptureRoutineUpgradeDetail(suggestion.statement ?? '', suggestion.intervalDays ?? 180)}${suggestion.scope != null && suggestion.scope != '*' ? ' ${l10n.knowledgeCaptureRoutineScopeDetail(suggestion.scope!)}' : ''} ${l10n.knowledgeCaptureRoutineReminderDetail}',
      _ => suggestion.reasonZh,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.sparkles,
                size: AppIconSizes.xs,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                headline,
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            detail,
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.knowledgeCaptureSuggestionReasonConfidence(
              suggestion.reasonZh,
              suggestion.confidence.toStringAsFixed(2),
            ),
            style: typography.xs.copyWith(color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
