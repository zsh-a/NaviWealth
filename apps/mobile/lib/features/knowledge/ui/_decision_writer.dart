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
import 'package:uuid/uuid.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/decision_context_snapper.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_segmented_row.dart';

const _kUuid = Uuid();

/// Two-mode toggle for the Decision rationale field — matches the
/// New Note sheet (`knowledge_inbox_page.dart`) so the author sees
/// rendered markdown before committing.
enum _RationaleMode { edit, preview }

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
  final List<_OptionDraft> _options = [
    _OptionDraft(),
    _OptionDraft(),
  ];
  String? _selectedLabel;
  final Set<String> _principleIds = <String>{};
  final Set<String> _assumptionIds = <String>{};
  DateTime? _reviewDate;
  bool _saving = false;
  _RationaleMode _rationaleMode = _RationaleMode.edit;

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
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
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
        id: _kUuid.v4(),
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
      title: 'New decision',
      subtitle: '决策即记忆 — question / options / rationale / review',
      footer: AppSheetFooter(
        submitLabel: _saving ? 'Saving…' : 'Save',
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
            label: const Text('Question'),
            hint: '"是否升级到 QQQ + BOXX 动态对冲?"',
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Options',
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
          for (var i = 0; i < _options.length; i++)
            _OptionEditorTile(
              draft: _options[i],
              index: i,
              selected: _options[i].labelCtrl.text.trim().isNotEmpty &&
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
              prefix: const Icon(FLucideIcons.plus, size: 14),
              onPress: () => setState(() {
                final draft = _OptionDraft();
                draft.labelCtrl.addListener(_onAnyChange);
                _options.add(draft);
              }),
              child: const Text('Add option'),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Rationale (Markdown)',
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
          KnowledgeSegmentedRow<_RationaleMode>(
            options: _RationaleMode.values,
            value: _rationaleMode,
            labelOf: (m) => switch (m) {
              _RationaleMode.edit => 'Edit',
              _RationaleMode.preview => 'Preview',
            },
            onChanged: (m) => setState(() => _rationaleMode = m),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_rationaleMode == _RationaleMode.edit)
            FTextField(
              control:
                  FTextFieldControl.managed(controller: _rationaleCtrl),
              hint: '为什么选这个 option — 限制条件、当时的判断',
              maxLines: 6,
              minLines: 3,
            )
          else
            Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.border),
              ),
              child: _rationaleCtrl.text.trim().isEmpty
                  ? Text(
                      'Nothing to preview — switch back to Edit and type.',
                      style: typography.sm
                          .copyWith(color: colors.mutedForeground),
                    )
                  : AiMarkdown(text: _rationaleCtrl.text),
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
            label: const Text('Expected outcome (optional)'),
            hint: '如何判断成功 — 用什么指标 / 信号',
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _reviewDate == null
                      ? 'Review date (optional)'
                      : 'Review on ${_reviewDate!.toLocal().toIso8601String().substring(0, 10)}',
                  style: typography.sm
                      .copyWith(color: colors.mutedForeground),
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
                child: Text(_reviewDate == null ? 'Pick' : 'Change'),
              ),
              if (_reviewDate != null) ...[
                const SizedBox(width: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => setState(() => _reviewDate = null),
                  child: const Text('Clear'),
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
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
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
                    selected
                        ? FLucideIcons.check
                        : FLucideIcons.circle,
                    size: 14,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: draft.labelCtrl,
                    ),
                    hint: 'Option ${index + 1}',
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  FButton.icon(
                    variant: FButtonVariant.outline,
                    onPress: onRemove,
                    child: const Icon(FLucideIcons.x, size: 14),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            FTextField(
              control: FTextFieldControl.managed(
                controller: draft.rationaleCtrl,
              ),
              hint: 'Why this option (optional)',
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
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (repo) => StreamBuilder<List<KnowledgePrinciple>>(
            stream: repo.watchPrinciples(ownerUserId: owner),
            builder: (context, principlesSnap) {
              return StreamBuilder<List<KnowledgeAssumption>>(
                stream: repo.watchAssumptions(ownerUserId: owner),
                builder: (context, assumptionsSnap) {
                  final principles = (principlesSnap.data ??
                          const <KnowledgePrinciple>[])
                      .where((p) => p.status == PrincipleStatus.active)
                      .toList(growable: false);
                  final assumptions = (assumptionsSnap.data ??
                          const <KnowledgeAssumption>[])
                      .where((a) => a.status == AssumptionStatus.active)
                      .toList(growable: false);
                  if (principles.isEmpty && assumptions.isEmpty) {
                    final typography = context.theme.typography;
                    final colors = context.theme.colors;
                    return Text(
                      '还没声明 Principles / Assumptions — Decision 可以先存,'
                      '之后回来挂引用',
                      style: typography.xs
                          .copyWith(color: colors.mutedForeground),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (principles.isNotEmpty) ...[
                        const _SectionLabel(text: 'Principles 引用'),
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
                        const _SectionLabel(text: 'Assumptions 引用'),
                        _CheckboxList(
                          items: assumptions
                              .map(
                                (a) => _CheckboxItem(
                                  id: a.id,
                                  label:
                                      '${a.statement} (conf ${a.confidence.toStringAsFixed(2)})',
                                  selected:
                                      assumptionIds.contains(a.id),
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
      style: context.theme.typography.sm
          .copyWith(fontWeight: FontWeight.w600),
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    item.selected
                        ? FLucideIcons.checkSquare2
                        : FLucideIcons.square,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(item.label, style: typography.sm),
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
      onPress: () =>
          Navigator.of(context).pop(now.add(Duration(days: days))),
      child: Text(label),
    );
    return AppSheet(
      title: 'Review date',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          choice(30, '+30 days'),
          const SizedBox(height: AppSpacing.s8),
          choice(90, '+90 days'),
          const SizedBox(height: AppSpacing.s8),
          choice(180, '+180 days'),
          const SizedBox(height: AppSpacing.s8),
          choice(365, '+1 year'),
        ],
      ),
    );
  }
}
