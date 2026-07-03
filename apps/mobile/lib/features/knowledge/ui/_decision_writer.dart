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
  return showAppFormSheet<void>(
    context: context,
    builder: (_) => const _DecisionWriter(),
  );
}

class _DecisionWriter extends ConsumerStatefulWidget {
  const _DecisionWriter();
  @override
  ConsumerState<_DecisionWriter> createState() => _DecisionWriterState();
}

class _DecisionWriterState extends ConsumerState<_DecisionWriter> {
  final _questionCtrl = TextEditingController();
  final _rationaleCtrl = TextEditingController();
  final _expectedCtrl = TextEditingController();
  final List<_OptionDraft> _options = [_OptionDraft(), _OptionDraft()];
  String? _selectedLabel;
  final Set<String> _principleIds = <String>{};
  final Set<String> _assumptionIds = <String>{};
  DateTime? _reviewDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _questionCtrl.addListener(_onAnyChange);
    for (final o in _options) {
      o.labelCtrl.addListener(_onAnyChange);
    }
  }

  void _onAnyChange() {
    if (!mounted) return;
    setState(() {
      _selectedLabel = _activeLabel(prefer: _selectedLabel);
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
    if (_options.where((o) => o.labelCtrl.text.trim().isNotEmpty).isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
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
      final selected = _selectedLabel ?? activeOptions.first.label;
      // Snapshot cross-domain "state of mind" at decision time
      // (§3 + §9 context_snapshot_json). Non-blocking — null on any
      // failure / no events, the column stays NULL and the detail page
      // skips the section.
      final snapper = ref.read(decisionContextSnapperProvider);
      final snapshot = await snapper.snapshot(
        ownerUserId: stamp.ownerUserId,
        now: stamp.now,
      );
      final decision = KnowledgeDecision(
        id: kKnowledgeUuid.v4(),
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
        status: DecisionStatus.active,
        contextSnapshot: snapshot,
        decidedAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertDecision(decision);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeDecisionWriterTitle,
      subtitle: l10n.knowledgeDecisionWriterSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || !_canSave,
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
                  },
                  onRemove: _options.length <= 2
                      ? null
                      : () => setState(() {
                          _options.removeAt(i).dispose();
                          _selectedLabel = _activeLabel();
                        }),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: AppQuietButton(
                  label: l10n.knowledgeDecisionAddOption,
                  prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
                  onPress: () => setState(() {
                    final draft = _OptionDraft();
                    draft.labelCtrl.addListener(_onAnyChange);
                    _options.add(draft);
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
                  _principleIds.contains(id)
                      ? _principleIds.remove(id)
                      : _principleIds.add(id);
                }),
                onAssumptionToggle: (id) => setState(() {
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
                      onPress: () => setState(() => _reviewDate = null),
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

  String? _activeLabel({String? prefer}) {
    final labels = _options
        .map((o) => o.labelCtrl.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (labels.isEmpty) return null;
    if (prefer != null && labels.contains(prefer)) return prefer;
    return labels.first;
  }
}
