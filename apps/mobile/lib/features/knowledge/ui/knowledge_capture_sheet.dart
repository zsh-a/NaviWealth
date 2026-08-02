/// Unified KnowledgeOS Capture sheet
/// (`docs/domains/knowledgeos-domain.md` §3 + §5 + §14).
///
/// One sheet, one textarea, one Save. Capture always persists a [KnowledgeNote]
/// and closes immediately. Repository change scheduling then runs Inbox Triage
/// and contradiction detection in the background, so capture never waits for
/// an LLM or asks the user to understand the domain taxonomy up front.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

part 'knowledge_capture_views.dart';

Future<void> showKnowledgeCaptureSheet(BuildContext context) {
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

  Future<void> _save() async {
    if (!_canSave) return;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = _stage;
    return AppSheet(
      title: l10n.knowledgeCaptureTitle,
      subtitle: l10n.knowledgeCaptureComposeSubtitle,
      footer: switch (stage) {
        _CaptureStage.composing => AppSheetFooter(
          submitLabel: l10n.knowledgeCaptureSave,
          cancelLabel: l10n.knowledgeCaptureCancel,
          enabled: _canSave,
          onSubmit: () {
            _save();
          },
        ),
        _CaptureStage.saving => null,
      },
      child: _ComposeBody(
        titleController: _titleCtrl,
        bodyController: _bodyCtrl,
      ),
    );
  }
}
