/// Unified KnowledgeOS Capture sheet
/// (`docs/domains/knowledgeos-domain.md` §3 + §5 + §14).
///
/// One sheet, one textarea, one Save. Default Auto mode persists a
/// [KnowledgeNote] and closes immediately. Repository change scheduling then
/// runs Inbox Triage and contradiction detection in the background, so capture
/// never waits for an LLM. Users can still choose a concrete kind up front;
/// structured kinds are validated and promoted explicitly during the save.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_promotion_service.dart';
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

enum _CaptureStage { composing, saving }

class _KnowledgeCaptureSheetState
    extends ConsumerState<_KnowledgeCaptureSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  _CaptureStage _stage = _CaptureStage.composing;
  CaptureKind? _manualKind;

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
    final text = <String>[
      if (_titleCtrl.text.trim().isNotEmpty) _titleCtrl.text.trim(),
      _bodyCtrl.text.trim(),
    ].join('\n');
    CaptureClassification? manualClassification;
    if (manualKind == CaptureKind.decision ||
        manualKind == CaptureKind.assumption ||
        manualKind == CaptureKind.experiment) {
      manualClassification = await const HeuristicCaptureClassifier().classify(
        text: text,
      );
      if (manualClassification.kind != manualKind) {
        if (mounted) {
          AppMessenger.show(
            context,
            ToastKind.warning,
            AppLocalizations.of(context).knowledgeCaptureNeedsStructure(
              _captureKindShortLabel(AppLocalizations.of(context), manualKind!),
            ),
          );
        }
        return;
      }
    }
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
        await _applyManualKind(
          note,
          manualKind,
          classification: manualClassification,
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      if (mounted) Navigator.of(context).pop();
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

  Future<void> _applyManualKind(
    KnowledgeNote note,
    CaptureKind kind, {
    CaptureClassification? classification,
  }) async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final title = note.title.trim();
    final statement = title.isNotEmpty
        ? knowledgeExcerpt(title, max: 60)
        : knowledgeExcerpt(note.bodyMd, max: 60);
    switch (kind) {
      case CaptureKind.routine:
      case CaptureKind.decision:
      case CaptureKind.principle:
      case CaptureKind.assumption:
      case CaptureKind.concept:
      case CaptureKind.experiment:
        final promotion = KnowledgePromotionService(
          repository: repo,
          ownerUserId: note.sync.ownerUserId,
          stamp: () async => _syncMetaFromStamp(await stamper.stamp()),
        );
        await promotion.promoteCapture(
          note: note,
          kind: kind,
          intervalDays: kind == CaptureKind.routine ? 180 : null,
          statement: statement,
          decisionOptions: classification?.decisionOptions ?? const <String>[],
          expectedOutcome: classification?.expectedOutcome,
          assumptionConfidence: classification?.assumptionConfidence,
          experimentMetrics:
              classification?.experimentMetrics ?? const <String>[],
          experimentMethod: classification?.experimentMethod,
        );
      case CaptureKind.note:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = _stage;
    return AppSheet(
      title: l10n.knowledgeCaptureTitle,
      subtitle: l10n.knowledgeCaptureComposeSubtitle,
      footer: switch (stage) {
        _CaptureStage.composing => AppSheetFooter(
          submitLabel: _manualKind == null
              ? l10n.knowledgeCaptureSave
              : l10n.knowledgeCaptureSaveTyped(
                  _captureKindShortLabel(l10n, _manualKind!),
                ),
          cancelLabel: l10n.knowledgeCaptureCancel,
          enabled: _canSave,
          onSubmit: () {
            _saveAndClassify();
          },
        ),
        _CaptureStage.saving => null,
      },
      child: _ComposeBody(
        titleController: _titleCtrl,
        bodyController: _bodyCtrl,
        selectedKind: _manualKind,
        onKindChanged: (kind) => setState(() => _manualKind = kind),
      ),
    );
  }
}

SyncMeta _syncMetaFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);
