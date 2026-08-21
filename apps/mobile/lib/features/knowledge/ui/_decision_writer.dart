/// KnowledgeOS Decision creation sheet
/// (`docs/domains/knowledgeos-domain.md` §1 + §3 + §9).
///
/// Decision is the highest-priority KnowledgeOS affordance per §1 —
/// this sheet is the user's primary write path. Field set mirrors the
/// `knowledge_decisions` table:
///
/// - question (required)
/// - options[] — dynamic list, each `{label, rationale?}`
/// - selectedLabel — one of `options[*].label`
/// - rationaleMd (markdown)
/// - principleIds[] / assumptionIds[] — multi-select from existing
/// - expectedOutcome / reviewDate — both optional
///
/// Status defaults to `active`. `contextSnapshotJson` is left null —
/// auto-capture is §14.2 P1 work.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/decision_context_snapper.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

part '_decision_writer_options.dart';
part '_decision_writer_references.dart';
part '_decision_writer_review_date.dart';

Future<void> showNewDecisionSheet(BuildContext context, WidgetRef _) {
  return showGuardedFormSheet<void>(
    context: context,
    builder: (_, dirty) => _DecisionWriter(dirty: dirty),
  );
}

Future<bool?> showEditDecisionSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeDecision decision,
) {
  return showGuardedFormSheet<bool>(
    context: context,
    builder: (_, dirty) => _DecisionWriter(initial: decision, dirty: dirty),
  );
}

class _DecisionWriter extends ConsumerStatefulWidget {
  const _DecisionWriter({this.initial, required this.dirty});

  final KnowledgeDecision? initial;
  final FormDirtyController dirty;
  @override
  ConsumerState<_DecisionWriter> createState() => _DecisionWriterState();
}

class _DecisionWriterState extends ConsumerState<_DecisionWriter> {
  late final _questionCtrl = TextEditingController(
    text: widget.initial?.question ?? '',
  );
  late final _rationaleCtrl = TextEditingController(
    text: widget.initial?.rationaleMd ?? '',
  );
  late final _expectedCtrl = TextEditingController(
    text: widget.initial?.expectedOutcome ?? '',
  );
  late final List<_OptionDraft> _options =
      widget.initial?.options.isNotEmpty == true
      ? <_OptionDraft>[
          for (final option in widget.initial!.options)
            _OptionDraft(
              label: option.label,
              rationale: option.rationale ?? '',
            ),
        ]
      : <_OptionDraft>[_OptionDraft(), _OptionDraft()];
  late String? _selectedLabel = widget.initial?.selectedLabel.isNotEmpty == true
      ? widget.initial!.selectedLabel
      : null;
  late final Set<String> _principleIds = <String>{
    ...?widget.initial?.principleIds,
  };
  late final Set<String> _assumptionIds = <String>{
    ...?widget.initial?.assumptionIds,
  };
  late DateTime? _reviewDate = widget.initial?.reviewDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _questionCtrl.addListener(_onAnyChange);
    for (final o in _options) {
      o.labelCtrl.addListener(_onAnyChange);
    }
    widget.dirty.bindTextControllers([
      _questionCtrl,
      _rationaleCtrl,
      _expectedCtrl,
      for (final option in _options) ...[
        option.labelCtrl,
        option.rationaleCtrl,
      ],
    ]);
  }

  void _onAnyChange() {
    if (!mounted) return;
    setState(() {
      final selected = _selectedLabel;
      if (selected != null && !_validOptionLabels.contains(selected)) {
        _selectedLabel = null;
      }
    });
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _rationaleCtrl.dispose();
    _expectedCtrl.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  bool get _canSave {
    if (_saving) return false;
    if (_questionCtrl.text.trim().isEmpty) return false;
    if (_validOptionLabels.length < 2) return false;
    return _selectedLabel != null &&
        _validOptionLabels.contains(_selectedLabel);
  }

  List<String> get _validOptionLabels => _options
      .map((option) => option.labelCtrl.text.trim())
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<void> _save() async {
    if (!_canSave) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final activeOptions = _options
          .where((o) => o.labelCtrl.text.trim().isNotEmpty)
          .map(
            (o) => DecisionOption(
              label: o.labelCtrl.text.trim(),
              rationale: o.rationaleCtrl.text.trim().isEmpty
                  ? null
                  : o.rationaleCtrl.text.trim(),
            ),
          )
          .toList(growable: false);
      final selected = _selectedLabel!;
      // Snapshot cross-domain "state of mind" at decision time
      // (§3 + §9 context_snapshot_json). Non-blocking — null on any
      // failure / no events, the column stays NULL and the detail page
      // skips the section.
      final initial = widget.initial;
      final snapshot =
          initial?.contextSnapshot ??
          await ref
              .read(decisionContextSnapperProvider)
              .snapshot(ownerUserId: stamp.ownerUserId, now: stamp.now);
      final decision = KnowledgeDecision(
        id: initial?.id ?? kKnowledgeUuid.v4(),
        question: _questionCtrl.text.trim(),
        options: activeOptions,
        selectedLabel: selected,
        rationaleMd: _rationaleCtrl.text,
        principleIds: _principleIds.toList(growable: false),
        assumptionIds: _assumptionIds.toList(growable: false),
        expectedOutcome: _expectedCtrl.text.trim().isEmpty
            ? null
            : _expectedCtrl.text.trim(),
        reviewDate: _reviewDate?.toUtc(),
        actualOutcomeMd: initial?.actualOutcomeMd,
        status: initial?.status ?? DecisionStatus.active,
        supersededByDecisionId: initial?.supersededByDecisionId,
        contextSnapshot: snapshot,
        decidedAt: initial?.decidedAt ?? stamp.now,
        mergedIntoId: initial?.mergedIntoId,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertDecision(decision);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(initial == null ? null : true);
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.initial != null;
    return AppSheet(
      title: editing
          ? l10n.knowledgeDecisionEditTitle
          : l10n.knowledgeDecisionWriterTitle,
      subtitle: editing
          ? l10n.knowledgeDecisionEditSubtitle
          : l10n.knowledgeDecisionWriterSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        enabled: _canSave,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _questionCtrl),
                label: Text(l10n.knowledgeDecisionQuestionLabel),
                hint: l10n.knowledgeDecisionQuestionHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeDecisionOptionsLabel,
            children: [
              for (var i = 0; i < _options.length; i++)
                _OptionEditorTile(
                  draft: _options[i],
                  index: i,
                  selected:
                      _options[i].labelCtrl.text.trim().isNotEmpty &&
                      _selectedLabel == _options[i].labelCtrl.text.trim(),
                  onSelect: () {
                    final label = _options[i].labelCtrl.text.trim();
                    if (label.isEmpty) return;
                    setState(() => _selectedLabel = label);
                    widget.dirty.markDirty();
                  },
                  onRemove: _options.length <= 2
                      ? null
                      : () => setState(() {
                          _options.removeAt(i).dispose();
                          _selectedLabel = null;
                          widget.dirty.markDirty();
                        }),
                ),
              if (_validOptionLabels.length < 2)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.knowledgeDecisionOptionsRequirement,
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.destructive,
                    ),
                  ),
                ),
              if (_validOptionLabels.length >= 2 && _selectedLabel == null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.knowledgeDecisionSelectionRequirement,
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.destructive,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: AppQuietButton(
                  label: l10n.knowledgeDecisionAddOption,
                  prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
                  onPress: () => setState(() {
                    final draft = _OptionDraft();
                    draft.labelCtrl.addListener(_onAnyChange);
                    widget.dirty.bindTextControllers([
                      draft.labelCtrl,
                      draft.rationaleCtrl,
                    ]);
                    _options.add(draft);
                    widget.dirty.markDirty();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            children: [
              MarkdownEditorWithPreview(
                controller: _rationaleCtrl,
                label: l10n.knowledgeWriterRationaleMarkdownLabel,
                hint: l10n.knowledgeDecisionRationaleHint,
                minLines: 3,
                maxLines: 6,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterReferencesSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              _PrincipleAssumptionPicker(
                principleIds: _principleIds,
                assumptionIds: _assumptionIds,
                onPrincipleToggle: (id) => setState(() {
                  widget.dirty.markDirty();
                  _principleIds.contains(id)
                      ? _principleIds.remove(id)
                      : _principleIds.add(id);
                }),
                onAssumptionToggle: (id) => setState(() {
                  widget.dirty.markDirty();
                  _assumptionIds.contains(id)
                      ? _assumptionIds.remove(id)
                      : _assumptionIds.add(id);
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterPlanningSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _expectedCtrl),
                label: Text(l10n.knowledgeDecisionExpectedOutcomeLabel),
                hint: l10n.knowledgeDecisionExpectedOutcomeHint,
                maxLines: 3,
                minLines: 1,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _reviewDate == null
                          ? l10n.knowledgeDecisionReviewDateOptional
                          : l10n.knowledgeDecisionReviewDateScheduled(
                              knowledgeDate(context, _reviewDate!, long: true),
                            ),
                      style: context.bodyCaptionStyle,
                    ),
                  ),
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: () async {
                      final picked = await _pickReviewDate(context);
                      if (picked != null) {
                        setState(() => _reviewDate = picked);
                        widget.dirty.markDirty();
                      }
                    },
                    child: Text(
                      _reviewDate == null
                          ? l10n.knowledgeDecisionReviewDateChoose
                          : l10n.knowledgeDecisionReviewDateChange,
                    ),
                  ),
                  if (_reviewDate != null) ...[
                    const SizedBox(width: AppSpacing.s8),
                    FButton(
                      variant: FButtonVariant.outline,
                      onPress: () {
                        setState(() => _reviewDate = null);
                        widget.dirty.markDirty();
                      },
                      child: Text(l10n.knowledgeDecisionClear),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
