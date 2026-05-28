/// Unified KnowledgeOS Capture sheet
/// (`docs/knowledgeos-domain.md` §3 + §5 + §14.2 P1).
///
/// One sheet, one textarea, one Save. Replaces the old Inbox-only
/// `_NewNoteSheet`. The capture always lands as a `KnowledgeNote` —
/// zero-latency, never blocks on AI. After save, [CaptureClassifier]
/// runs a synchronous heuristic over the same text; when it spots a
/// stronger fit (today: Routine), the sheet swaps its body for an
/// inline "AI 建议升级" card with ✓ / ✗:
///
/// - ✓ promotes: writes the structured target row + soft-deletes the
///   temp Note in a single transaction (`upsertRoutine` + `upsertNote
///   (deletedAt = now)`). Sheet closes.
/// - ✗ keeps the Note. Sheet closes.
///
/// LLM-augmented classification is the §14.2 P1 swap; the public seam
/// is [CaptureClassifier.classify] and changes nothing about the sheet.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/capture_classifier.dart';
import '../data/capture_kind.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

Future<void> showKnowledgeCaptureSheet(
  BuildContext context,
  WidgetRef ref,
) {
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
/// `saving` → upsertNote in flight. `suggesting` → note saved,
/// classification said "upgrade", waiting for ✓ / ✗. `applying` →
/// promote in flight.
enum _CaptureStage { composing, saving, suggesting, applying }

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
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
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
      // body. Joining keeps the heuristic simple.
      final text = <String>[
        if (_titleCtrl.text.trim().isNotEmpty) _titleCtrl.text.trim(),
        _bodyCtrl.text.trim(),
      ].join('\n');
      final classification =
          const CaptureClassifier().classify(text: text);
      if (!mounted) return;
      if (classification.isUpgrade) {
        setState(() {
          _savedNote = note;
          _suggestion = classification;
          _stage = _CaptureStage.suggesting;
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _stage = _CaptureStage.composing);
      }
      rethrow;
    }
  }

  Future<void> _acceptUpgrade() async {
    final note = _savedNote;
    final suggestion = _suggestion;
    if (note == null || suggestion == null) return;
    setState(() => _stage = _CaptureStage.applying);
    try {
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);

      // Write the target row + soft-delete the temp Note. Same stamp
      // is fine: both writes belong to the same logical "promotion"
      // event from the user's perspective.
      switch (suggestion.kind) {
        case CaptureKind.routine:
          final stamp = await stamper.stamp();
          final intervalDays = suggestion.intervalDays ?? 180;
          await repo.upsertRoutine(
            KnowledgeRoutine(
              id: kKnowledgeUuid.v4(),
              statement: suggestion.statement ?? note.title,
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
        case CaptureKind.note:
        case CaptureKind.decision:
        case CaptureKind.principle:
        case CaptureKind.assumption:
        case CaptureKind.concept:
        case CaptureKind.experiment:
          // Other kinds aren't classified yet (heuristics land in §14.2
          // P1). Treat as no-op so the sheet still closes cleanly even
          // if a future heuristic accidentally reaches this branch.
          break;
      }

      if (suggestion.kind != CaptureKind.note) {
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
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _stage = _CaptureStage.suggesting);
      }
      rethrow;
    }
  }

  void _dismissSuggestion() {
    // ✗ → keep the saved Note as-is and close. The Note survived the
    // save step so dismissing just means the user agreed it's a Note.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    return AppSheet(
      title: stage == _CaptureStage.suggesting
          ? 'AI 建议升级'
          : '写一条想法',
      subtitle: stage == _CaptureStage.suggesting
          ? '一段输入就够 — 类型 / 字段由 AI 抽取，你一键确认'
          : '自由格式 Markdown — AI 会在保存后建议升级为 Routine / Decision 等',
      footer: stage == _CaptureStage.suggesting
          ? null
          : AppSheetFooter(
              submitLabel: stage == _CaptureStage.saving ? '保存中…' : '保存',
              busy: !_canSave,
              onSubmit: () {
                _saveAndClassify();
              },
            ),
      child: switch (stage) {
        _CaptureStage.composing ||
        _CaptureStage.saving =>
          _ComposeBody(
            titleController: _titleCtrl,
            bodyController: _bodyCtrl,
          ),
        _CaptureStage.suggesting ||
        _CaptureStage.applying =>
          _SuggestionBody(
            suggestion: _suggestion!,
            applying: stage == _CaptureStage.applying,
            onAccept: _acceptUpgrade,
            onDismiss: _dismissSuggestion,
          ),
      },
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
          label: const Text('标题（可选）'),
          hint: '"港卡需要定期活跃"',
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: bodyController),
          label: const Text('内容'),
          hint: '"港卡每 6 个月做一次活跃交易，否则会休眠"',
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
    required this.applying,
    required this.onAccept,
    required this.onDismiss,
  });
  final CaptureClassification suggestion;
  final bool applying;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final headline = switch (suggestion.kind) {
      CaptureKind.routine => '看起来是一个定期事项',
      CaptureKind.decision => '看起来在权衡某个选项',
      CaptureKind.assumption => '看起来在声明一条信念',
      CaptureKind.principle => '看起来在声明一条原则',
      CaptureKind.concept => '看起来在定义一个概念',
      CaptureKind.experiment => '看起来在描述一个实验',
      CaptureKind.note => '保留为 Note',
    };
    final detail = switch (suggestion.kind) {
      CaptureKind.routine =>
        '会建一条 Routine:"${suggestion.statement ?? ''}",每 ${suggestion.intervalDays ?? 180} 天提醒一次'
            '${suggestion.scope != null && suggestion.scope != '*' ? '，scope = ${suggestion.scope}' : ''}。'
            'AI 会在到期前 7 天自动提醒。',
      _ => suggestion.reasonZh,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                    size: 14,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Text(
                    headline,
                    style: typography.sm
                        .copyWith(fontWeight: FontWeight.w600),
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
                '原因:${suggestion.reasonZh} · 置信度 ${suggestion.confidence.toStringAsFixed(2)}',
                style: typography.xs
                    .copyWith(color: colors.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: applying ? null : onDismiss,
              child: const Text('保留为 Note'),
            ),
            const SizedBox(width: AppSpacing.s8),
            FButton(
              onPress: applying ? null : onAccept,
              child: Text(applying ? '应用中…' : '✓ 应用建议'),
            ),
          ],
        ),
      ],
    );
  }
}
