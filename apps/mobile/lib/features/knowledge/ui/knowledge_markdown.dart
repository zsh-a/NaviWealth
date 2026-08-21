part of '_widgets.dart';

/// Standards-compliant, settled-document renderer for KnowledgeOS.
///
/// Knowledge documents deliberately do not share the tolerant streaming
/// parser used by AI chat. CommonMark/GFM is parsed into an AST once per
/// source change, then rendered through the local design system. Raw HTML and
/// remote images are never executed or fetched.
class KnowledgeMarkdown extends StatefulWidget {
  const KnowledgeMarkdown({
    super.key,
    required this.text,
    this.selectable = true,
  });

  final String text;
  final bool selectable;

  @override
  State<KnowledgeMarkdown> createState() => _KnowledgeMarkdownState();
}

class _KnowledgeMarkdownState extends State<KnowledgeMarkdown> {
  String? _cachedText;
  List<md.Node> _cachedNodes = const <md.Node>[];

  List<md.Node> get _nodes {
    if (_cachedText == widget.text) return _cachedNodes;
    _cachedText = widget.text;
    _cachedNodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    ).parse(widget.text);
    return _cachedNodes;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes;
    if (nodes.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      children.add(_block(context, nodes[i]));
      if (i < nodes.length - 1) {
        children.add(SizedBox(height: _gap(nodes[i], nodes[i + 1])));
      }
    }
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  TextStyle _bodyStyle(BuildContext context) => TypographyTokens.bodyLarge
      .copyWith(height: 1.68, color: context.theme.colors.foreground);

  Widget _block(BuildContext context, md.Node node, {int depth = 0}) {
    final base = _bodyStyle(context);
    if (node is md.Text) return _rich(node, base);
    if (node is! md.Element) return const SizedBox.shrink();
    final tag = node.tag;
    if (_headingLevel(tag) case final level?) {
      final style = switch (level) {
        1 => TypographyTokens.headlineLarge,
        2 => TypographyTokens.headlineMedium,
        3 => TypographyTokens.headlineSmall,
        _ => TypographyTokens.titleLarge,
      }.copyWith(color: context.theme.colors.foreground);
      return Semantics(
        header: true,
        child: _richChildren(node.children, style),
      );
    }
    return switch (tag) {
      'p' => _paragraph(context, node, base),
      'blockquote' => _quote(context, node),
      'ul' => _list(context, node, ordered: false, depth: depth),
      'ol' => _list(context, node, ordered: true, depth: depth),
      'pre' => _codeBlock(context, node),
      'table' => _table(context, node),
      'hr' => _rule(context),
      'section' => _footnotes(context, node),
      _ => _fallbackBlock(context, node, depth: depth),
    };
  }

  Widget _quote(BuildContext context, md.Element element) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.softTint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(
          left: BorderSide(color: colors.primary, width: AppStroke.accent),
        ),
      ),
      child: _nestedBlocks(context, element.children),
    );
  }

  Widget _list(
    BuildContext context,
    md.Element element, {
    required bool ordered,
    required int depth,
  }) {
    final items = (element.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((child) => child.tag == 'li')
        .toList(growable: false);
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s6),
          _listItem(
            context,
            items[i],
            marker: ordered ? '${start + i}.' : null,
            depth: depth,
          ),
        ],
      ],
    );
  }

  Widget _listItem(
    BuildContext context,
    md.Element item, {
    required String? marker,
    required int depth,
  }) {
    final checked = _taskState(item);
    final bodyStyle = _bodyStyle(context);
    final content = <Widget>[];
    final inlineRun = <md.Node>[];

    void flushInlineRun() {
      if (inlineRun.isEmpty) return;
      content.add(_richChildren(List<md.Node>.of(inlineRun), bodyStyle));
      inlineRun.clear();
    }

    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') continue;
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
        flushInlineRun();
        content.add(const SizedBox(height: AppSpacing.s6));
        content.add(
          _list(context, child, ordered: child.tag == 'ol', depth: depth + 1),
        );
      } else if (child is md.Element && child.tag == 'p') {
        flushInlineRun();
        content.add(_richChildren(child.children, bodyStyle));
      } else if (child is md.Element && _isBlockTag(child.tag)) {
        flushInlineRun();
        content.add(_block(context, child, depth: depth));
      } else {
        inlineRun.add(child);
      }
    }
    flushInlineRun();
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: AppSpacing.s10,
              top: AppSpacing.s4,
            ),
            child: checked == null
                ? _KnowledgeListMarker(marker: marker)
                : _KnowledgeTaskMarker(checked: checked),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  bool? _taskState(md.Element item) {
    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') {
        return child.attributes['checked'] == 'true';
      }
      if (child is md.Element) {
        for (final nested in child.children ?? const <md.Node>[]) {
          if (nested is md.Element && nested.tag == 'input') {
            return nested.attributes['checked'] == 'true';
          }
        }
      }
    }
    return null;
  }

  Widget _codeBlock(BuildContext context, md.Element element) {
    final code = (element.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .firstWhere(
          (child) => child.tag == 'code',
          orElse: () => md.Element.text('code', element.textContent),
        );
    final className = code.attributes['class'] ?? '';
    final language = className.startsWith('language-')
        ? className.substring('language-'.length)
        : '';
    if (language == 'flow') {
      final diagram = FlowParser.parse(code.textContent);
      if (diagram != null) return FlowDiagramWidget(diagram: diagram);
    }
    return _KnowledgeCodeBlock(code: code.textContent, language: language);
  }

  Widget _table(BuildContext context, md.Element table) {
    final rows = _descendants(table, 'tr').toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    final parsedRows = <List<md.Element>>[
      for (final row in rows)
        (row.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .where((cell) => cell.tag == 'th' || cell.tag == 'td')
            .toList(growable: false),
    ];
    final columns = parsedRows.fold<int>(
      0,
      (current, row) => math.max(current, row.length),
    );
    if (columns == 0) return const SizedBox.shrink();
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.knowledgeMarkdownTableLabel(rows.length, columns),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : columns * 136.0;
          final width = math.max(available, columns * 136.0);
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Table(
                    defaultColumnWidth: const FlexColumnWidth(),
                    border: TableBorder(
                      horizontalInside: BorderSide(color: colors.border),
                    ),
                    children: [
                      for (
                        var rowIndex = 0;
                        rowIndex < parsedRows.length;
                        rowIndex++
                      )
                        TableRow(
                          decoration: BoxDecoration(
                            color: rowIndex == 0
                                ? colors.muted.withValues(
                                    alpha: AppOpacity.prominent,
                                  )
                                : null,
                          ),
                          children: [
                            for (var column = 0; column < columns; column++)
                              _tableCell(
                                context,
                                column < parsedRows[rowIndex].length
                                    ? parsedRows[rowIndex][column]
                                    : null,
                                header: rowIndex == 0,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableCell(
    BuildContext context,
    md.Element? cell, {
    required bool header,
  }) {
    final baseStyle = _bodyStyle(
      context,
    ).copyWith(fontSize: TypographyTokens.bodyMedium.fontSize, height: 1.5);
    final style = header
        ? TypographyTokens.semiboldEmphasis(baseStyle)
        : baseStyle;
    final alignment = switch (cell?.attributes['align']) {
      'center' => AlignmentDirectional.center,
      'right' => AlignmentDirectional.centerEnd,
      _ => AlignmentDirectional.centerStart,
    };
    return Semantics(
      header: header,
      child: Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: cell == null
            ? const SizedBox.shrink()
            : _richChildren(cell.children, style),
      ),
    );
  }

  Iterable<md.Element> _descendants(md.Element root, String tag) sync* {
    for (final child in root.children ?? const <md.Node>[]) {
      if (child is! md.Element) continue;
      if (child.tag == tag) yield child;
      yield* _descendants(child, tag);
    }
  }

  Widget _rule(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
    child: Container(
      height: AppStroke.hairline,
      color: context.theme.colors.border,
    ),
  );

  Widget _footnotes(BuildContext context, md.Element element) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _rule(context),
        const SizedBox(height: AppSpacing.s8),
        _nestedBlocks(context, element.children),
      ],
    );
  }

  Widget _fallbackBlock(
    BuildContext context,
    md.Element element, {
    required int depth,
  }) {
    final children = element.children ?? const <md.Node>[];
    if (children.any(
      (child) => child is md.Element && _isBlockTag(child.tag),
    )) {
      return _nestedBlocks(context, children, depth: depth);
    }
    return _richChildren(children, _bodyStyle(context));
  }

  Widget _nestedBlocks(
    BuildContext context,
    List<md.Node>? nodes, {
    int depth = 0,
  }) {
    final children = <Widget>[];
    final source = nodes ?? const <md.Node>[];
    for (var i = 0; i < source.length; i++) {
      children.add(_block(context, source[i], depth: depth));
      if (i < source.length - 1) {
        children.add(SizedBox(height: _gap(source[i], source[i + 1])));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _rich(md.Node node, TextStyle style) =>
      _richChildren(<md.Node>[node], style);

  Widget _richChildren(List<md.Node>? nodes, TextStyle style) {
    final span = TextSpan(children: _inline(nodes, style));
    return widget.selectable ? AppSelectableText.rich(span) : Text.rich(span);
  }

  List<InlineSpan> _inline(List<md.Node>? nodes, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style));
        continue;
      }
      if (node is! md.Element) continue;
      final nextStyle = switch (node.tag) {
        'strong' || 'b' => TypographyTokens.semiboldEmphasis(style),
        'em' || 'i' => style.copyWith(fontStyle: FontStyle.italic),
        'del' => style.copyWith(decoration: TextDecoration.lineThrough),
        'sup' => style.copyWith(
          fontSize: (style.fontSize ?? 16) - 2,
          color: context.theme.colors.primary,
        ),
        _ => style,
      };
      switch (node.tag) {
        case 'br':
          spans.add(TextSpan(text: '\n', style: style));
        case 'code':
          spans.add(_inlineCode(node.textContent, style));
        case 'a':
          spans.add(_link(node, style));
        case 'img':
          spans.add(_image(node, style));
        case 'input':
          break;
        default:
          spans.addAll(_inline(node.children, nextStyle));
      }
    }
    return spans;
  }

  InlineSpan _inlineCode(String text, TextStyle base) {
    final colors = context.theme.colors;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: colors.muted.withValues(alpha: AppOpacity.prominent),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          text,
          style: base.copyWith(
            fontFamily: TypographyTokens.fontFamilyMono,
            fontSize: (base.fontSize ?? 16) - 1,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  InlineSpan _link(md.Element element, TextStyle base) {
    final label = element.textContent;
    final href = element.attributes['href'] ?? '';
    final style = base.copyWith(
      color: context.theme.colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: context.theme.colors.primary.withValues(
        alpha: AppOpacity.disabled,
      ),
    );
    if (!_isAllowedExternalLink(href)) {
      return TextSpan(text: label, style: style);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _KnowledgeLink(label: label, url: href, style: style),
    );
  }

  /// A paragraph whose only content is one attachment image renders as a
  /// block-level image instead of an inline chip in the text run.
  Widget _paragraph(BuildContext context, md.Element node, TextStyle base) {
    final meaningful = (node.children ?? const <md.Node>[])
        .where((child) => child is! md.Text || child.text.trim().isNotEmpty)
        .toList(growable: false);
    if (meaningful.length == 1 && meaningful.first is md.Element) {
      final only = meaningful.first as md.Element;
      final attachmentId = knowledgeAttachmentIdFromSrc(
        only.attributes['src'] ?? '',
      );
      if (only.tag == 'img' && attachmentId != null) {
        return KnowledgeAttachmentImage(
          attachmentId: attachmentId,
          alt: only.attributes['alt'] ?? only.textContent,
          block: true,
        );
      }
    }
    return _richChildren(node.children, base);
  }

  InlineSpan _image(md.Element element, TextStyle base) {
    final description = element.attributes['alt']?.trim().isNotEmpty == true
        ? element.attributes['alt']!.trim()
        : element.textContent.trim().isNotEmpty
        ? element.textContent.trim()
        : element.attributes['src'] ?? '';
    final label = AppLocalizations.of(
      context,
    ).knowledgeMarkdownImageLabel(description);
    final attachmentId = knowledgeAttachmentIdFromSrc(
      element.attributes['src'] ?? '',
    );
    if (attachmentId != null) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: KnowledgeAttachmentImage(
          attachmentId: attachmentId,
          alt: description,
        ),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        image: true,
        label: label,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            color: context.theme.colors.muted.withValues(
              alpha: AppOpacity.prominent,
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FLucideIcons.image,
                size: AppIconSizes.xs,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                label,
                style: TypographyTokens.bodySmall.copyWith(color: base.color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _gap(md.Node current, md.Node next) {
    final currentTag = current is md.Element ? current.tag : '';
    final nextTag = next is md.Element ? next.tag : '';
    if (_headingLevel(nextTag) != null) return AppSpacing.s28;
    if (_headingLevel(currentTag) != null) return AppSpacing.s10;
    if (currentTag == 'li' || nextTag == 'li') return AppSpacing.s6;
    if (currentTag == 'hr' || nextTag == 'hr') return AppSpacing.s16;
    if ({'pre', 'blockquote', 'table'}.contains(currentTag) ||
        {'pre', 'blockquote', 'table'}.contains(nextTag)) {
      return AppSpacing.s20;
    }
    return AppSpacing.s14;
  }

  int? _headingLevel(String tag) {
    if (!RegExp(r'^h[1-6]$').hasMatch(tag)) return null;
    return int.parse(tag.substring(1));
  }

  bool _isBlockTag(String tag) => <String>{
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'ul',
    'ol',
    'pre',
    'table',
    'hr',
    'section',
  }.contains(tag);
}

class _KnowledgeListMarker extends StatelessWidget {
  const _KnowledgeListMarker({required this.marker});

  final String? marker;

  @override
  Widget build(BuildContext context) {
    if (marker != null) {
      return SizedBox(
        width: AppSpacing.s24,
        child: Text(
          marker!,
          textAlign: TextAlign.end,
          style: TypographyTokens.bodyMedium.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s6),
      child: Container(
        width: AppStroke.indicator,
        height: AppStroke.indicator,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.theme.colors.primary,
        ),
      ),
    );
  }
}

class _KnowledgeTaskMarker extends StatelessWidget {
  const _KnowledgeTaskMarker({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      checked: checked,
      readOnly: true,
      child: ExcludeSemantics(
        child: Container(
          width: AppSpacing.s16,
          height: AppSpacing.s16,
          decoration: BoxDecoration(
            color: checked ? colors.primary : null,
            border: Border.all(
              color: checked ? colors.primary : colors.border,
              width: AppStroke.thin,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: checked
              ? Icon(
                  FLucideIcons.check,
                  size: AppSpacing.s10,
                  color: colors.primaryForeground,
                )
              : null,
        ),
      ),
    );
  }
}

class _KnowledgeCodeBlock extends StatefulWidget {
  const _KnowledgeCodeBlock({required this.code, required this.language});

  final String code;
  final String language;

  @override
  State<_KnowledgeCodeBlock> createState() => _KnowledgeCodeBlockState();
}

class _KnowledgeCodeBlockState extends State<_KnowledgeCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.prominent),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s12,
              AppSpacing.s4,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language,
                    style: TypographyTokens.labelSmall.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.aiChatMessageCopy,
                  child: FTooltip(
                    tipBuilder: (_, _) => Text(l10n.aiChatMessageCopy),
                    child: AppTappable(
                      onPress: _copy,
                      child: SizedBox.square(
                        dimension: AppControlHeights.touchTarget,
                        child: Icon(
                          _copied ? FLucideIcons.check : FLucideIcons.copy,
                          size: AppIconSizes.sm,
                          color: _copied
                              ? colors.primary
                              : colors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s2,
              AppSpacing.s12,
              AppSpacing.s12,
            ),
            child: AppSelectableText(
              widget.code,
              style: TypographyTokens.bodySmall.copyWith(
                fontFamily: TypographyTokens.fontFamilyMono,
                height: 1.55,
                color: colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(Motion.copyFeedback);
    if (mounted) setState(() => _copied = false);
  }
}

class _KnowledgeLink extends StatelessWidget {
  const _KnowledgeLink({
    required this.label,
    required this.url,
    required this.style,
  });

  final String label;
  final String url;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: label,
      hint: url,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _confirmAndOpenKnowledgeLink(context, url),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

bool _isAllowedExternalLink(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      const <String>{'http', 'https', 'mailto'}.contains(uri.scheme);
}

Future<void> _confirmAndOpenKnowledgeLink(
  BuildContext context,
  String url,
) async {
  if (!_isAllowedExternalLink(url)) return;
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.aiChatLinkConfirmTitle),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.aiChatLinkConfirmBody, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s8),
        Container(
          padding: AppPageRhythm.densePadding,
          decoration: BoxDecoration(
            color: context.theme.colors.muted.withValues(
              alpha: AppOpacity.prominent,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.theme.colors.border),
          ),
          child: AppSelectableText(
            url,
            maxLines: 4,
            style: TypographyTokens.bodySmall.copyWith(
              fontFamily: TypographyTokens.fontFamilyMono,
              color: context.theme.colors.foreground,
            ),
          ),
        ),
      ],
    ),
    confirmLabel: l10n.aiChatLinkOpen,
    cancelLabel: l10n.commonCancel,
  );
  if (confirmed != true || !context.mounted) return;
  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    AppMessenger.show(context, ToastKind.error, l10n.aiChatLinkOpenFailed);
  }
}
