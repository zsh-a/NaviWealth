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
class MarkdownEditorWithPreview extends ConsumerStatefulWidget {
  const MarkdownEditorWithPreview({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.minLines = 3,
    this.maxLines = 6,
    this.initialPreview = false,
  });

  final TextEditingController controller;

  /// Optional label rendered above the toggle. Pass `null` when the
  /// surrounding sheet already labels the field.
  final String? label;

  final String? hint;
  final int minLines;
  final int maxLines;

  /// Opens the compact mobile layout on the rendered document. Editing is
  /// still one tap away; wide layouts continue to show both panes.
  final bool initialPreview;

  @override
  ConsumerState<MarkdownEditorWithPreview> createState() =>
      _MarkdownEditorWithPreviewState();
}

enum _MarkdownMode { edit, preview }

class _MarkdownEditorWithPreviewState
    extends ConsumerState<MarkdownEditorWithPreview> {
  late _MarkdownMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialPreview ? _MarkdownMode.preview : _MarkdownMode.edit;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MarkdownEditorWithPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onTextChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _editorPane(
                      context,
                      title: l10n.knowledgeMarkdownEdit,
                      wide: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: _previewPane(
                      context,
                      title: l10n.knowledgeMarkdownPreview,
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                AnimatedSwitcher(
                  duration: AppMotionPolicy.duration(context, Motion.fast),
                  child: _mode == _MarkdownMode.edit
                      ? _editorPane(context, key: const ValueKey('edit'))
                      : _previewPane(context, key: const ValueKey('preview')),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _editorPane(
    BuildContext context, {
    Key? key,
    String? title,
    bool wide = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final editor = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleBold,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _toggleBold,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _insertLink,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _insertLink,
      },
      // Desktop drag-and-drop: dropping an image file onto the editor
      // imports it as an attachment and inserts the markdown reference.
      child: DropTarget(
        onDragDone: (details) =>
            _importDroppedImages(details.files, AppLocalizations.of(context)),
        child: FTextField(
          control: FTextFieldControl.managed(controller: widget.controller),
          hint: widget.hint,
          minLines: wide ? math.max(widget.minLines, 6) : widget.minLines,
          maxLines: wide ? math.max(widget.maxLines, 12) : widget.maxLines,
        ),
      ),
    );
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(title, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s6),
        ],
        _MarkdownToolbar(
          actions: [
            _MarkdownToolbarAction(
              icon: FLucideIcons.bold,
              label: l10n.knowledgeMarkdownBold,
              onPress: _toggleBold,
            ),
            _MarkdownToolbarAction(
              icon: FLucideIcons.link,
              label: l10n.knowledgeMarkdownLink,
              onPress: _insertLink,
            ),
            _MarkdownToolbarAction(
              icon: FLucideIcons.list,
              label: l10n.knowledgeMarkdownBulletedList,
              onPress: () => _prefixLines('- '),
            ),
            _MarkdownToolbarAction(
              icon: FLucideIcons.quote,
              label: l10n.knowledgeMarkdownQuote,
              onPress: () => _prefixLines('> '),
            ),
            _MarkdownToolbarAction(
              icon: FLucideIcons.code,
              label: l10n.knowledgeMarkdownInlineCode,
              onPress: () => _wrapSelection('`', '`'),
            ),
          ],
          trailing: KnowledgeImageInsertButton(controller: widget.controller),
        ),
        const SizedBox(height: AppSpacing.s6),
        editor,
      ],
    );
  }

  Widget _previewPane(BuildContext context, {Key? key, String? title}) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(title, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s6),
        ],
        SoftCard.flat(
          padding: AppPageRhythm.cardPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
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

  void _toggleBold() => _wrapSelection('**', '**');

  Future<void> _importDroppedImages(
    List<DropItem> files,
    AppLocalizations l10n,
  ) async {
    for (final file in files) {
      final ext = file.name.split('.').last.toLowerCase();
      if (!kKnowledgeAttachmentImageTypes.containsKey(ext)) continue;
      final attachment = await importKnowledgeImageBytes(
        ref,
        fileName: file.name,
        bytes: await file.readAsBytes(),
      );
      if (!mounted) return;
      if (attachment == null) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeImageImportFailed,
        );
        continue;
      }
      insertKnowledgeAttachmentMarkdown(widget.controller, attachment);
    }
  }

  void _insertLink() {
    final value = widget.controller.value;
    final selection = _safeSelection(value);
    final selected = value.text.substring(selection.start, selection.end);
    final replacement = '[${selected.isEmpty ? '' : selected}](https://)';
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    final cursor = selected.isEmpty
        ? selection.start + 1
        : selection.start + replacement.length - 1;
    widget.controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  void _wrapSelection(String prefix, String suffix) {
    final value = widget.controller.value;
    final selection = _safeSelection(value);
    final selected = value.text.substring(selection.start, selection.end);
    final replacement = '$prefix$selected$suffix';
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    final nextSelection = selected.isEmpty
        ? TextSelection.collapsed(offset: selection.start + prefix.length)
        : TextSelection(
            baseOffset: selection.start + prefix.length,
            extentOffset: selection.end + prefix.length,
          );
    widget.controller.value = value.copyWith(
      text: text,
      selection: nextSelection,
      composing: TextRange.empty,
    );
  }

  void _prefixLines(String prefix) {
    final value = widget.controller.value;
    final selection = _safeSelection(value);
    final lineStart = selection.start == 0
        ? 0
        : value.text.lastIndexOf('\n', selection.start - 1) + 1;
    final nextBreak = value.text.indexOf('\n', selection.end);
    final lineEnd = nextBreak == -1 ? value.text.length : nextBreak;
    final selectedLines = value.text.substring(lineStart, lineEnd);
    final replacement = selectedLines
        .split('\n')
        .map((line) => '$prefix$line')
        .join('\n');
    final text = value.text.replaceRange(lineStart, lineEnd, replacement);
    widget.controller.value = value.copyWith(
      text: text,
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  TextSelection _safeSelection(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: value.text.length);
    }
    return TextSelection(
      baseOffset: math.min(selection.start, value.text.length),
      extentOffset: math.min(selection.end, value.text.length),
    );
  }
}

class _MarkdownToolbarAction {
  const _MarkdownToolbarAction({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({required this.actions, this.trailing});

  final List<_MarkdownToolbarAction> actions;

  /// Optional trailing affordance (the image insert menu). Hidden by its own
  /// logic where attachment storage is unsupported.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s4,
      children: [
        for (final action in actions)
          FTooltip(
            tipBuilder: (_, _) => Text(action.label),
            child: Semantics(
              button: true,
              label: action.label,
              child: AppTappable(
                onPress: action.onPress,
                child: SizedBox.square(
                  dimension: AppControlHeights.touchTarget,
                  child: Icon(
                    action.icon,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ?trailing,
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
