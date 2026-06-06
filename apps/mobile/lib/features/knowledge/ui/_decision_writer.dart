/// KnowledgeOS Decision creation sheet
/// (`docs/knowledgeos-domain.md` §1 + §3 + §9).
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

Future<void> showNewDecisionSheet(BuildContext context, WidgetRef ref) {
  return showAppFormSheet<void>(
    context: context,
    builder: (_) => _DecisionWriter(ref: ref),
  );
}

class _DecisionWriter extends StatefulWidget {
  const _DecisionWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_DecisionWriter> createState() => _DecisionWriterState();
}

class _DecisionWriterState extends State<_DecisionWriter> {
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
      final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper = await widget.ref.read(mutationStamperProvider.future);
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
      final snapper = widget.ref.read(decisionContextSnapperProvider);
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
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return AppSheet(
      title: AppLocalizations.of(context).knowledgeDecisionWriterTitle,
      subtitle: AppLocalizations.of(context).knowledgeDecisionWriterSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving
            ? AppLocalizations.of(context).commonSaving
            : AppLocalizations.of(context).commonSave,
        cancelLabel: AppLocalizations.of(context).commonCancel,
        busy: _saving || !_canSave,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _questionCtrl),
            label: Text(
              AppLocalizations.of(context).knowledgeDecisionQuestionLabel,
            ),
            hint: AppLocalizations.of(context).knowledgeDecisionQuestionHint,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            AppLocalizations.of(context).knowledgeDecisionOptionsLabel,
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
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
            child: FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
              onPress: () => setState(() {
                final draft = _OptionDraft();
                draft.labelCtrl.addListener(_onAnyChange);
                _options.add(draft);
              }),
              child: Text(
                AppLocalizations.of(context).knowledgeDecisionAddOption,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          MarkdownEditorWithPreview(
            controller: _rationaleCtrl,
            label: AppLocalizations.of(
              context,
            ).knowledgeWriterRationaleMarkdownLabel,
            hint: AppLocalizations.of(context).knowledgeDecisionRationaleHint,
            minLines: 3,
            maxLines: 6,
          ),
          const SizedBox(height: AppSpacing.s12),
          _PrincipleAssumptionPicker(
            ref: widget.ref,
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
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _expectedCtrl),
            label: Text(
              AppLocalizations.of(
                context,
              ).knowledgeDecisionExpectedOutcomeLabel,
            ),
            hint: AppLocalizations.of(
              context,
            ).knowledgeDecisionExpectedOutcomeHint,
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _reviewDate == null
                      ? AppLocalizations.of(
                          context,
                        ).knowledgeDecisionReviewDateOptional
                      : AppLocalizations.of(
                          context,
                        ).knowledgeDecisionReviewDateScheduled(
                          knowledgeDate(context, _reviewDate!, long: true),
                        ),
                  style: typography.sm.copyWith(color: colors.mutedForeground),
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
                      ? AppLocalizations.of(
                          context,
                        ).knowledgeDecisionReviewDateChoose
                      : AppLocalizations.of(
                          context,
                        ).knowledgeDecisionReviewDateChange,
                ),
              ),
              if (_reviewDate != null) ...[
                const SizedBox(width: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => setState(() => _reviewDate = null),
                  child: Text(
                    AppLocalizations.of(context).knowledgeDecisionClear,
                  ),
                ),
              ],
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

class _OptionDraft {
  _OptionDraft({String label = '', String rationale = ''})
    : labelCtrl = TextEditingController(text: label),
      rationaleCtrl = TextEditingController(text: rationale);
  final TextEditingController labelCtrl;
  final TextEditingController rationaleCtrl;
  void dispose() {
    labelCtrl.dispose();
    rationaleCtrl.dispose();
  }
}

class _OptionEditorTile extends StatelessWidget {
  const _OptionEditorTile({
    required this.draft,
    required this.index,
    required this.selected,
    required this.onSelect,
    this.onRemove,
  });
  final _OptionDraft draft;
  final int index;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s8),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? colors.primary : colors.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FButton.icon(
                  variant: selected
                      ? FButtonVariant.primary
                      : FButtonVariant.outline,
                  onPress: onSelect,
                  child: Icon(
                    selected ? FLucideIcons.check : FLucideIcons.circle,
                    size: AppIconSizes.xs,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: draft.labelCtrl,
                    ),
                    hint: AppLocalizations.of(
                      context,
                    ).knowledgeDecisionOptionLabelHint(index + 1),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  FButton.icon(
                    variant: FButtonVariant.outline,
                    onPress: onRemove,
                    child: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            FTextField(
              control: FTextFieldControl.managed(
                controller: draft.rationaleCtrl,
              ),
              hint: AppLocalizations.of(
                context,
              ).knowledgeDecisionOptionRationaleHint,
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrincipleAssumptionPicker extends ConsumerWidget {
  const _PrincipleAssumptionPicker({
    required this.ref,
    required this.principleIds,
    required this.assumptionIds,
    required this.onPrincipleToggle,
    required this.onAssumptionToggle,
  });
  final WidgetRef ref;
  final Set<String> principleIds;
  final Set<String> assumptionIds;
  final ValueChanged<String> onPrincipleToggle;
  final ValueChanged<String> onAssumptionToggle;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          ),
          error: (e, _) => KnowledgeErrorState(
            title: AppLocalizations.of(context).knowledgeLoadFailed('$e'),
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
            density: KnowledgeStateDensity.section,
          ),
          data: (repo) => StreamBuilder<List<KnowledgePrinciple>>(
            stream: repo.watchPrinciples(ownerUserId: owner),
            builder: (context, principlesSnap) {
              if (principlesSnap.hasError) {
                return KnowledgeErrorState(
                  title: AppLocalizations.of(
                    context,
                  ).knowledgeLoadFailed('${principlesSnap.error}'),
                  density: KnowledgeStateDensity.section,
                );
              }
              return StreamBuilder<List<KnowledgeAssumption>>(
                stream: repo.watchAssumptions(ownerUserId: owner),
                builder: (context, assumptionsSnap) {
                  if (assumptionsSnap.hasError) {
                    return KnowledgeErrorState(
                      title: AppLocalizations.of(
                        context,
                      ).knowledgeLoadFailed('${assumptionsSnap.error}'),
                      density: KnowledgeStateDensity.section,
                    );
                  }
                  final principles =
                      (principlesSnap.data ?? const <KnowledgePrinciple>[])
                          .where((p) => p.status == PrincipleStatus.active)
                          .toList(growable: false);
                  final assumptions =
                      (assumptionsSnap.data ?? const <KnowledgeAssumption>[])
                          .where((a) => a.status == AssumptionStatus.active)
                          .toList(growable: false);
                  if (principles.isEmpty && assumptions.isEmpty) {
                    final typography = context.theme.typography;
                    final colors = context.theme.colors;
                    return Text(
                      AppLocalizations.of(
                        context,
                      ).knowledgeDecisionNoReferenceCandidates,
                      style: typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (principles.isNotEmpty) ...[
                        _SectionLabel(
                          text: AppLocalizations.of(
                            context,
                          ).knowledgeDetailPrinciplesTitle,
                        ),
                        _CheckboxList(
                          items: principles
                              .map(
                                (p) => _CheckboxItem(
                                  id: p.id,
                                  label: p.statement,
                                  selected: principleIds.contains(p.id),
                                ),
                              )
                              .toList(growable: false),
                          onToggle: onPrincipleToggle,
                        ),
                      ],
                      if (assumptions.isNotEmpty) ...[
                        if (principles.isNotEmpty)
                          const SizedBox(height: AppSpacing.s8),
                        _SectionLabel(
                          text: AppLocalizations.of(
                            context,
                          ).knowledgeDetailAssumptionsTitle,
                        ),
                        _CheckboxList(
                          items: assumptions
                              .map(
                                (a) => _CheckboxItem(
                                  id: a.id,
                                  label:
                                      '${a.statement}（conf ${a.confidence.toStringAsFixed(2)}）',
                                  selected: assumptionIds.contains(a.id),
                                ),
                              )
                              .toList(growable: false),
                          onToggle: onAssumptionToggle,
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s4),
    child: Text(
      text,
      style: context.theme.typography.sm.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _CheckboxItem {
  const _CheckboxItem({
    required this.id,
    required this.label,
    required this.selected,
  });
  final String id;
  final String label;
  final bool selected;
}

class _CheckboxList extends StatelessWidget {
  const _CheckboxList({required this.items, required this.onToggle});
  final List<_CheckboxItem> items;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggle(item.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Row(
                children: [
                  Icon(
                    item.selected
                        ? FLucideIcons.checkSquare2
                        : FLucideIcons.square,
                    size: AppIconSizes.xs,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: typography.sm,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<DateTime?> _pickReviewDate(BuildContext context) async {
  final now = DateTime.now();
  // Minimal date picker — Forui has no native one; we offer +30 / +90
  // / +180 day shortcuts in a small sheet. Custom dates land later
  // (P2; calendar widget is a separate dependency call).
  return showAppFormSheet<DateTime>(
    context: context,
    builder: (sheetContext) => _ReviewDateSheet(now: now),
  );
}

class _ReviewDateSheet extends StatelessWidget {
  const _ReviewDateSheet({required this.now});
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    Widget choice(int days, String label) => FButton(
      variant: FButtonVariant.outline,
      onPress: () => Navigator.of(context).pop(now.add(Duration(days: days))),
      child: Text(label),
    );
    return AppSheet(
      title: AppLocalizations.of(context).knowledgeDecisionReviewDateTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          choice(
            30,
            AppLocalizations.of(context).knowledgeDecisionReviewDateInDays(30),
          ),
          const SizedBox(height: AppSpacing.s8),
          choice(
            90,
            AppLocalizations.of(context).knowledgeDecisionReviewDateInDays(90),
          ),
          const SizedBox(height: AppSpacing.s8),
          choice(
            180,
            AppLocalizations.of(context).knowledgeDecisionReviewDateInDays(180),
          ),
          const SizedBox(height: AppSpacing.s8),
          choice(
            365,
            AppLocalizations.of(context).knowledgeDecisionReviewDateInOneYear,
          ),
        ],
      ),
    );
  }
}
