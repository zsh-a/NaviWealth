import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/visual/ai_markdown.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Plain Markdown source editing with an explicit rendered preview.
///
/// KnowledgeOS deliberately stays source-first rather than becoming a rich
/// text editor. The preview uses the same renderer as other trusted app AI
/// surfaces, so supported syntax and visual styling remain consistent.
class KnowledgeMarkdownEditor extends StatefulWidget {
  const KnowledgeMarkdownEditor({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 4,
    this.maxLines,
    this.enabled = true,
    this.initialPreview = false,
    this.editorKey,
    this.previewKey,
  });

  final TextEditingController controller;
  final String label;
  final int minLines;
  final int? maxLines;
  final bool enabled;
  final bool initialPreview;
  final Key? editorKey;
  final Key? previewKey;

  @override
  State<KnowledgeMarkdownEditor> createState() =>
      _KnowledgeMarkdownEditorState();
}

class _KnowledgeMarkdownEditorState extends State<KnowledgeMarkdownEditor> {
  late bool _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_preview)
              Expanded(
                child: Text(widget.label, style: context.captionLabelStyle),
              )
            else
              const Spacer(),
            AppTappable(
              onPress: widget.enabled
                  ? () => setState(() => _preview = !_preview)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _preview ? FLucideIcons.codeXml : FLucideIcons.eye,
                      size: AppIconSizes.xs,
                      color: context.theme.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Text(
                      _preview
                          ? l10n.knowledgeMarkdownEditAction
                          : l10n.knowledgeMarkdownPreviewAction,
                      style: context.captionLabelStyle.copyWith(
                        color: context.theme.colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        if (_preview)
          AppGroupedSurface(
            key: widget.previewKey,
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: widget.controller.text.trim().isEmpty
                ? Text(
                    l10n.knowledgeMarkdownEmptyPreview,
                    style: context.bodyCaptionStyle,
                  )
                : AiMarkdown(text: widget.controller.text),
          )
        else
          FTextField(
            key: widget.editorKey,
            control: FTextFieldControl.managed(controller: widget.controller),
            label: Text(widget.label),
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            enabled: widget.enabled,
          ),
      ],
    );
  }
}
