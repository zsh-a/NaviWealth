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
                child: FButton(
                  variant: FButtonVariant.outline,
                  prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
                  onPress: () => setState(() {
                    final draft = _OptionDraft();
                    draft.labelCtrl.addListener(_onAnyChange);
                    _options.add(draft);
                  }),
                  child: Text(l10n.knowledgeDecisionAddOption),
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
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterPlanningSectionTitle,
            collapsible: true,
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
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
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
                FRadio(
                  value: selected,
                  onChange: draft.labelCtrl.text.trim().isEmpty
                      ? null
                      : (_) => onSelect(),
                  semanticsLabel: AppLocalizations.of(
                    context,
                  ).knowledgeDecisionOptionLabelHint(index + 1),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          KnowledgeSelectableRow(
            label: item.label,
            selected: item.selected,
            onPress: () => onToggle(item.id),
          ),
      ],
    );
  }
}

Future<DateTime?> _pickReviewDate(BuildContext context) async {
  final now = DateTime.now();
  // Minimal date picker — Forui has no native calendar widget; we offer common
  // shortcuts plus a strict YYYY-MM-DD custom input without adding a dependency.
  return showAppFormSheet<DateTime>(
    context: context,
    builder: (sheetContext) => _ReviewDateSheet(now: now),
  );
}

class _ReviewDateSheet extends StatefulWidget {
  const _ReviewDateSheet({required this.now});
  final DateTime now;

  @override
  State<_ReviewDateSheet> createState() => _ReviewDateSheetState();
}

class _ReviewDateSheetState extends State<_ReviewDateSheet> {
  final _customCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseCustomDate(BuildContext context) {
    final raw = _customCtrl.text.trim();
    final l10n = AppLocalizations.of(context);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) {
      setState(() => _error = l10n.knowledgeDecisionReviewDateInvalid);
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      setState(() => _error = l10n.knowledgeDecisionReviewDateInvalid);
      return null;
    }
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    if (parsed.isBefore(today)) {
      setState(() => _error = l10n.knowledgeDecisionReviewDatePast);
      return null;
    }
    setState(() => _error = null);
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    Widget choice(int days, String label) => FButton(
      variant: FButtonVariant.outline,
      onPress: () =>
          Navigator.of(context).pop(widget.now.add(Duration(days: days))),
      child: Text(label),
    );
    return AppSheet(
      title: l10n.knowledgeDecisionReviewDateTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          choice(30, l10n.knowledgeDecisionReviewDateInDays(30)),
          const SizedBox(height: AppSpacing.s8),
          choice(90, l10n.knowledgeDecisionReviewDateInDays(90)),
          const SizedBox(height: AppSpacing.s8),
          choice(180, l10n.knowledgeDecisionReviewDateInDays(180)),
          const SizedBox(height: AppSpacing.s8),
          choice(365, l10n.knowledgeDecisionReviewDateInOneYear),
          const SizedBox(height: AppSpacing.s12),
          const FDivider(),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _customCtrl),
            label: Text(l10n.knowledgeDecisionReviewDateCustomLabel),
            hint: l10n.knowledgeDecisionReviewDateCustomHint,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              _error!,
              style: typography.xs.copyWith(color: colors.destructive),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          FButton(
            onPress: () {
              final parsed = _parseCustomDate(context);
              if (parsed != null) Navigator.of(context).pop(parsed);
            },
            child: Text(l10n.knowledgeDecisionReviewDateCustomApply),
          ),
        ],
      ),
    );
  }
}
