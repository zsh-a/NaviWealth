import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_rewrite_client.dart';
import 'widgets/knowledge_markdown_editor.dart';

Future<KnowledgeRewriteDraft?> showKnowledgeRewriteSheet({
  required BuildContext context,
  required KnowledgeRewriteKind kind,
  required String objectId,
  required String heading,
  required String content,
}) {
  return showAppFormSheet<KnowledgeRewriteDraft>(
    context: context,
    builder: (_) => _KnowledgeRewriteSheet(
      kind: kind,
      objectId: objectId,
      locale: Localizations.localeOf(context).toLanguageTag(),
      heading: heading,
      content: content,
    ),
  );
}

class _KnowledgeRewriteSheet extends ConsumerStatefulWidget {
  const _KnowledgeRewriteSheet({
    required this.kind,
    required this.objectId,
    required this.locale,
    required this.heading,
    required this.content,
  });

  final KnowledgeRewriteKind kind;
  final String objectId;
  final String locale;
  final String heading;
  final String content;

  @override
  ConsumerState<_KnowledgeRewriteSheet> createState() =>
      _KnowledgeRewriteSheetState();
}

class _KnowledgeRewriteSheetState
    extends ConsumerState<_KnowledgeRewriteSheet> {
  final _heading = TextEditingController();
  final _content = TextEditingController();
  var _style = KnowledgeRewriteStyle.clear;
  var _loading = false;
  var _hasDraft = false;
  String? _error;
  late String _sourceHeading;
  late String _sourceContent;

  @override
  void initState() {
    super.initState();
    _sourceHeading = widget.heading.trim();
    _sourceContent = widget.content.trim();
    _restoreSource();
  }

  @override
  void dispose() {
    _heading.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final client = ref.watch(knowledgeRewriteClientProvider);
    final (headingLabel, contentLabel) = switch (widget.kind) {
      KnowledgeRewriteKind.note => (
        l10n.knowledgeCaptureTitleField,
        l10n.knowledgeCaptureBodyField,
      ),
      KnowledgeRewriteKind.decision => (
        l10n.knowledgeDecisionQuestionLabel,
        l10n.knowledgeWriterRationaleMarkdownLabel,
      ),
    };
    return AppSheet(
      title: l10n.knowledgeRewriteTitle,
      subtitle: l10n.knowledgeRewriteSubtitle,
      footer: client == null
          ? null
          : AppSheetFooter(
              submitKey: const Key('knowledge-rewrite-submit'),
              submitLabel: _hasDraft
                  ? l10n.knowledgeRewriteUseDraft
                  : l10n.knowledgeRewriteGenerate,
              cancelLabel: l10n.commonCancel,
              onSubmit: _hasDraft ? _apply : () => _generate(client),
              busy: _loading,
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStatusBanner(
            compact: true,
            kind: client == null ? AppStatusKind.warning : AppStatusKind.info,
            message: client == null
                ? l10n.knowledgeRewriteUnavailable
                : l10n.knowledgeRewriteDisclosure,
          ),
          if (client != null) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.knowledgeRewriteStyleLabel,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s6),
            SegmentedRow<KnowledgeRewriteStyle>(
              options: KnowledgeRewriteStyle.values,
              value: _style,
              labelOf: (style) => switch (style) {
                KnowledgeRewriteStyle.clear => l10n.knowledgeRewriteStyleClear,
                KnowledgeRewriteStyle.concise =>
                  l10n.knowledgeRewriteStyleConcise,
                KnowledgeRewriteStyle.structured =>
                  l10n.knowledgeRewriteStyleStructured,
              },
              onChanged: _loading ? (_) {} : _changeStyle,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s12),
              AppStatusBanner(
                compact: true,
                kind: AppStatusKind.error,
                message: _error!,
              ),
            ],
            const SizedBox(height: AppSpacing.s16),
            Text(
              _hasDraft
                  ? l10n.knowledgeRewritePreviewTitle
                  : l10n.knowledgeRewriteOriginalTitle,
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            AbsorbPointer(
              absorbing: _loading,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FTextField(
                    control: FTextFieldControl.managed(controller: _heading),
                    label: Text(headingLabel),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  KnowledgeMarkdownEditor(
                    key: ValueKey<bool>(_hasDraft),
                    controller: _content,
                    label: contentLabel,
                    minLines: 6,
                    maxLines: 12,
                    enabled: !_loading,
                    initialPreview: _hasDraft,
                    editorKey: const Key('knowledge-rewrite-content-editor'),
                    previewKey: const Key('knowledge-rewrite-markdown-preview'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _changeStyle(KnowledgeRewriteStyle style) {
    setState(() {
      _style = style;
      _hasDraft = false;
      _error = null;
      _restoreSource();
    });
  }

  void _restoreSource() {
    _heading.text = _sourceHeading;
    _content.text = _sourceContent;
  }

  Future<void> _generate(KnowledgeRewriteClient client) async {
    final sourceHeading = _heading.text.trim();
    final sourceContent = _content.text.trim();
    if (sourceHeading.isEmpty && sourceContent.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).knowledgeRewriteEmpty,
      );
      return;
    }
    _sourceHeading = sourceHeading;
    _sourceContent = sourceContent;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final draft = await client.rewrite(
        KnowledgeRewriteRequest(
          kind: widget.kind,
          style: _style,
          objectId: widget.objectId,
          locale: widget.locale,
          heading: sourceHeading,
          content: sourceContent,
        ),
      );
      if (!mounted) return;
      _heading.text = draft.heading;
      _content.text = draft.content;
      setState(() => _hasDraft = true);
    } on KnowledgeRewriteEmptyResponseException catch (error, stackTrace) {
      if (!mounted) return;
      userSafeErrorMessage(
        context,
        error,
        stackTrace: stackTrace,
        operation: 'rewrite knowledge',
      );
      setState(() {
        _error = AppLocalizations.of(context).knowledgeRewriteEmptyResponse;
      });
    } on FormatException catch (error, stackTrace) {
      if (!mounted) return;
      userSafeErrorMessage(
        context,
        error,
        stackTrace: stackTrace,
        operation: 'rewrite knowledge',
      );
      setState(() {
        _error = AppLocalizations.of(context).knowledgeRewriteInvalidResponse;
      });
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).knowledgeRewriteFailed(
          userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'rewrite knowledge',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply() {
    final heading = _heading.text.trim();
    final content = _content.text.trim();
    if (heading.isEmpty && content.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).knowledgeRewriteEmpty,
      );
      return;
    }
    Navigator.of(context)
        .pop(KnowledgeRewriteDraft(heading: heading, content: content));
  }
}
