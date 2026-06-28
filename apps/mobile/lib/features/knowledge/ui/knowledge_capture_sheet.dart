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
            duration: motionDuration(context, Motion.medium),
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
            duration: motionDuration(context, Motion.medium),
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

Widget _captureStageTransition(Widget child, Animation<double> animation) {
  final curved = animation.drive(CurveTween(curve: Motion.standardDecelerate));
  final offset = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(curved);
  return FadeTransition(
    opacity: curved,
    child: SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: SlideTransition(position: offset, child: child),
    ),
  );
}

Widget _capturePreviewTransition(Widget child, Animation<double> animation) {
  final curved = animation.drive(CurveTween(curve: Motion.standardDecelerate));
  final offset = Tween<Offset>(
    begin: const Offset(0, -0.06),
    end: Offset.zero,
  ).animate(curved);
  return FadeTransition(
    opacity: curved,
    child: SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: SlideTransition(position: offset, child: child),
    ),
  );
}

class _ClassifyingBody extends StatelessWidget {
  const _ClassifyingBody({super.key, required this.onSkip});

  /// Bail out of the wait — the Note is already saved, the in-flight
  /// classifier becomes an orphan and its eventual result is dropped
  /// by the sheet's `mounted` guard. Useful for slow thinking models
  /// (mimo / Claude extended thinking) where the round-trip can take
  /// 20-30 s.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Skeleton shimmer lines to suggest "AI is reading your text"
          // instead of a bare progress bar.
          ...List.generate(3, (i) {
            final widths = <double>[double.infinity, 200, 140];
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < 2 ? AppSpacing.s8 : AppSpacing.s0,
              ),
              child: SkeletonBox(
                height: 14,
                width: widths[i],
                radius: AppRadius.xs,
              ),
            );
          }),
          const SizedBox(height: AppSpacing.s16),
          Text(
            l10n.knowledgeCaptureClassifyingBody,
            textAlign: TextAlign.center,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.center,
            child: AppQuietButton(
              label: l10n.knowledgeCaptureSkipClassification,
              onPress: onSkip,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedCapturePreview extends StatelessWidget {
  const _SavedCapturePreview({
    super.key,
    required this.sectionTitle,
    required this.promoted,
    required this.title,
    required this.body,
  });

  final String sectionTitle;
  final bool promoted;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final hasTitle = title.trim().isNotEmpty;
    return KnowledgeWriterSection(
      title: sectionTitle,
      trailing: Icon(
        FLucideIcons.fileCheck,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTitle) ...[
              Text(
                l10n.knowledgeCaptureTitleDiffLabel,
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              _CaptureSharedTextLine(
                text: knowledgeExcerpt(title),
                promoted: promoted,
                style: typography.body.sm,
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            Text(
              l10n.knowledgeCaptureBodyDiffLabel,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s2),
            _CaptureSharedTextLine(
              text: knowledgeExcerpt(body),
              promoted: promoted,
              style: context.bodyCaptionStyle,
              maxLines: 3,
            ),
          ],
        ),
      ],
    );
  }
}

class _CaptureSharedTextLine extends StatelessWidget {
  const _CaptureSharedTextLine({
    required this.text,
    required this.promoted,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final bool promoted;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: promoted ? 1 : 0),
      duration: motionDuration(context, Motion.medium),
      curve: Motion.standardDecelerate,
      builder: (context, progress, child) {
        final scale = 0.985 + 0.015 * progress;
        final dy = -6 * (1 - progress);
        final color = Color.lerp(
          style.color ?? colors.foreground,
          colors.primary,
          progress * 0.18,
        );
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: motionDuration(context, Motion.fast),
              curve: Motion.standardDecelerate,
              style: style.copyWith(color: color),
              child: child!,
            ),
          ),
        );
      },
      child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ComposeBody extends StatelessWidget {
  const _ComposeBody({
    super.key,
    required this.titleController,
    required this.bodyController,
    required this.selectedKind,
    required this.onKindChanged,
  });
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeWriterSection(
      title: l10n.knowledgeCaptureTitle,
      children: [
        _CaptureKindPicker(
          selectedKind: selectedKind,
          onChanged: onKindChanged,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: titleController),
          label: Text(l10n.knowledgeCaptureTitleField),
          hint: l10n.knowledgeCaptureTitleHint,
        ),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          label: Text(l10n.knowledgeCaptureBodyField),
          hint: l10n.knowledgeCaptureBodyHint,
          minLines: 4,
          maxLines: 8,
        ),
      ],
    );
  }
}

class _CaptureKindPicker extends StatelessWidget {
  const _CaptureKindPicker({
    required this.selectedKind,
    required this.onChanged,
  });

  final CaptureKind? selectedKind;
  final ValueChanged<CaptureKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <_CaptureKindOption>[
      _CaptureKindOption(null, l10n.knowledgeCaptureKindAuto),
      for (final kind in CaptureKind.values)
        _CaptureKindOption(kind, _captureKindShortLabel(l10n, kind)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.knowledgeCaptureTypeLabel, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                _CaptureKindChip(
                  label: options[i].label,
                  selected: options[i].kind == selectedKind,
                  onTap: () => onChanged(options[i].kind),
                ),
                if (i != options.length - 1)
                  const SizedBox(width: AppSpacing.s6),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptureKindChip extends StatelessWidget {
  const _CaptureKindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: motionDuration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: AppOpacity.subtle)
              : colors.muted,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.prominent)
                : colors.border.withValues(alpha: AppOpacity.muted),
          ),
        ),
        child: Text(
          label,
          style: context.captionLabelStyle.copyWith(
            color: selected ? colors.primary : colors.foreground,
          ),
        ),
      ),
    );
  }
}

class _CaptureKindOption {
  const _CaptureKindOption(this.kind, this.label);

  final CaptureKind? kind;
  final String label;
}

String _captureKindShortLabel(AppLocalizations l10n, CaptureKind kind) {
  return switch (kind) {
    CaptureKind.note => l10n.knowledgeCaptureKindNote,
    CaptureKind.routine => l10n.knowledgeCaptureKindRoutine,
    CaptureKind.decision => l10n.knowledgeCaptureKindDecision,
    CaptureKind.principle => l10n.knowledgeCaptureKindPrinciple,
    CaptureKind.assumption => l10n.knowledgeCaptureKindAssumption,
    CaptureKind.concept => l10n.knowledgeCaptureKindConcept,
    CaptureKind.experiment => l10n.knowledgeCaptureKindExperiment,
  };
}

class _SuggestionBody extends StatelessWidget {
  const _SuggestionBody({
    super.key,
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
              style: context.captionStyle,
            ),
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
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final titleChanged =
        suggestion.polishedTitle != null &&
        suggestion.polishedTitle != originalTitle;
    final bodyChanged =
        suggestion.polishedBody != null &&
        suggestion.polishedBody != originalBody;
    return KnowledgeWriterSection(
      title: l10n.knowledgeCapturePolishedVersionTitle,
      trailing: Icon(
        FLucideIcons.wand,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s4),
        // Original — muted, stricken
        Container(
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            knowledgeExcerpt(before),
            style: context.bodyCaptionStyle.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: colors.mutedForeground,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        // Arrow indicator
        Icon(
          FLucideIcons.arrowDown,
          size: AppIconSizes.xs,
          color: colors.primary,
        ),
        const SizedBox(height: AppSpacing.s4),
        // Improved — primary tint
        Container(
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: AppOpacity.subtle),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: colors.primary.withValues(alpha: AppOpacity.light),
            ),
          ),
          child: Text(
            knowledgeExcerpt(after),
            style: typography.body.sm.copyWith(color: colors.foreground),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
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
    return KnowledgeWriterSection(
      title: headline,
      trailing: Icon(
        FLucideIcons.sparkles,
        size: AppIconSizes.xs,
        color: colors.primary,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail, style: context.bodyCaptionStyle),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.knowledgeCaptureSuggestionReasonConfidence(
                suggestion.reasonZh,
                suggestion.confidence.toStringAsFixed(2),
              ),
              style: context.captionStyle,
            ),
          ],
        ),
      ],
    );
  }
}
