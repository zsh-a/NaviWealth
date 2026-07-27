part of '_widgets.dart';

/// Edit/Preview toggle for a Markdown text field.
///
/// Use anywhere a user authors free-form markdown that the rest of the
/// app will render via [KnowledgeMarkdown] — the toggle lets them check
/// the rendered output before submitting. Currently driving the Note body,
/// Decision rationale, Principle rationale, Concept summary and
/// Experiment method fields; that's the entire markdown-write surface
/// in KnowledgeOS.
///
/// Owns the segmented control's mode state; the caller owns the
/// text [controller].
class MarkdownEditorWithPreview extends StatefulWidget {
  const MarkdownEditorWithPreview({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.minLines = 3,
    this.maxLines = 6,
  });

  final TextEditingController controller;

  /// Optional label rendered above the toggle. Pass `null` when the
  /// surrounding sheet already labels the field.
  final String? label;

  final String? hint;
  final int minLines;
  final int maxLines;

  @override
  State<MarkdownEditorWithPreview> createState() =>
      _MarkdownEditorWithPreviewState();
}

enum _MarkdownMode { edit, preview }

class _MarkdownEditorWithPreviewState extends State<MarkdownEditorWithPreview> {
  _MarkdownMode _mode = _MarkdownMode.edit;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
        ],
        SegmentedRow<_MarkdownMode>(
          options: _MarkdownMode.values,
          value: _mode,
          labelOf: (m) => switch (m) {
            _MarkdownMode.edit => l10n.knowledgeMarkdownEdit,
            _MarkdownMode.preview => l10n.knowledgeMarkdownPreview,
          },
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (_mode == _MarkdownMode.edit)
          FTextField(
            control: FTextFieldControl.managed(controller: widget.controller),
            hint: widget.hint,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
          )
        else
          // Match detail reading skin (no muted "disabled field" fill).
          SoftCard.flat(
            padding: AppPageRhythm.densePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: widget.controller.text.trim().isEmpty
                  ? Text(
                      l10n.knowledgeMarkdownPreviewEmpty,
                      style: context.bodyCaptionStyle.copyWith(
                        color: colors.mutedForeground,
                      ),
                    )
                  : KnowledgeMarkdown(text: widget.controller.text),
            ),
          ),
      ],
    );
  }
}

/// Section shell for KnowledgeOS writer sheets.
///
/// Keeps dense forms scannable without turning every field into its own card.
/// Use [collapsible] for optional/reference-heavy sections.
class KnowledgeWriterSection extends StatefulWidget {
  const KnowledgeWriterSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool collapsible;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<KnowledgeWriterSection> createState() => _KnowledgeWriterSectionState();
}

class _KnowledgeWriterSectionState extends State<KnowledgeWriterSection> {
  late bool _expanded = widget.initiallyExpanded || !widget.collapsible;

  @override
  void didUpdateWidget(covariant KnowledgeWriterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.collapsible && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: context.labelStyle),
              if (widget.subtitle != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  widget.subtitle!,
                  style: context.captionStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.s8),
          widget.trailing!,
        ],
        if (widget.collapsible) ...[
          const SizedBox(width: AppSpacing.s8),
          Icon(
            _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
            size: AppIconSizes.xs,
            color: colors.mutedForeground,
          ),
        ],
      ],
    );
    return SoftCard.flat(
      padding: AppPageRhythm.densePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.collapsible)
            AppTappable(
              onPress: () => setState(() => _expanded = !_expanded),
              child: header,
            )
          else
            header,
          AnimatedSwitcher(
            duration: AppMotionPolicy.duration(context, Motion.fast),
            child: _expanded
                ? Column(
                    key: const ValueKey<String>('expanded'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: AppSpacing.s12),
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.s12),
                        widget.children[i],
                      ],
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey<String>('collapsed')),
          ),
        ],
      ),
    );
  }
}
