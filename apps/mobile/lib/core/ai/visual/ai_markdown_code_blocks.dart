part of 'ai_markdown.dart';

class _MdCode extends _MdBlock {
  const _MdCode({required this.code, this.language, required this.closed});

  final String code;
  final String? language;
  final bool closed;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final lang = (language ?? '').trim();
    final l10n = AppLocalizations.of(context);
    final mono = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
      fontSize: (base.fontSize ?? TypographyTokens.bodySmall.fontSize!) - 1,
      height: 1.5,
      color: AiTone.onSurface(context),
    );

    final spans = _CodeTinter.tint(code, mono, context);
    if (trailing != null) spans.add(trailing);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context).withValues(alpha: AppOpacity.scrim),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AiTone.outline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lang.isNotEmpty || closed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                AppSpacing.s6,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lang.isEmpty ? '' : lang,
                      style: AiType.meta(context)
                          .copyWith(color: AiTone.muted(context)),
                    ),
                  ),
                  if (closed)
                    _CopyButton(
                      text: code,
                      tooltip: l10n.aiChatMessageCopy,
                      confirm: l10n.aiChatMessageCopied,
                    ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s12,
              (lang.isNotEmpty || closed) ? AppSpacing.s2 : AppSpacing.s8,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            child: _NoSoftWrap(
              child: _selectableRich(spans, selectable: selectable),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSoftWrap extends StatelessWidget {
  const _NoSoftWrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
}

class _MdTable extends _MdBlock {
  const _MdTable({
    required this.header,
    required this.aligns,
    required this.rows,
  });

  final List<String> header;
  final List<TextAlign> aligns;
  final List<List<String>> rows;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final cols = header.length;
    final outline = AiTone.outline(context);
    final headerStyle = AiType.tableHeader(context, base);
    final headerBg = AiTone.surfaceTint(context)
        .withValues(alpha: AppOpacity.disabled);

    final normalizedRows = <List<String>>[];
    for (final row in rows) {
      if (row.length == cols) {
        normalizedRows.add(row);
      } else if (row.length > cols) {
        normalizedRows.add(row.sublist(0, cols));
      } else {
        normalizedRows.add([...row, ...List.filled(cols - row.length, '')]);
      }
    }

    Widget cell(
      String text,
      TextStyle style,
      TextAlign align, {
      Color? background,
    }) {
      final spans = _InlineParser.parse(text, style, context);
      return Container(
        color: background,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s6,
        ),
        alignment: switch (align) {
          TextAlign.right => Alignment.centerRight,
          TextAlign.center => Alignment.center,
          _ => Alignment.centerLeft,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80),
          child: selectable
              ? SelectableText.rich(TextSpan(children: spans), textAlign: align)
              : Text.rich(TextSpan(children: spans), textAlign: align),
        ),
      );
    }

    final table = Table(
      border: TableBorder.all(color: outline, width: AppStroke.hairline),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [
            for (var i = 0; i < cols; i++)
              cell(
                header[i],
                headerStyle,
                i < aligns.length ? aligns[i] : TextAlign.left,
              ),
          ],
        ),
        for (final row in normalizedRows)
          TableRow(
            children: [
              for (var i = 0; i < cols; i++)
                cell(
                  row[i],
                  base,
                  i < aligns.length ? aligns[i] : TextAlign.left,
                ),
            ],
          ),
      ],
    );

    final wrapped = Semantics(
      container: true,
      label: 'Table, ${normalizedRows.length + 1} rows, $cols columns',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    );

    if (trailing == null) return wrapped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        wrapped,
        const SizedBox(height: AppSpacing.s4),
        Text.rich(TextSpan(children: [trailing])),
      ],
    );
  }
}

class _MdFlowBlock extends _MdBlock {
  const _MdFlowBlock(this.diagram);

  final FlowDiagram diagram;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final widget = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: FlowDiagramWidget(diagram: diagram),
    );
    if (trailing == null) return widget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget,
        const SizedBox(height: AppSpacing.s4),
        Text.rich(TextSpan(children: [trailing])),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.text,
    required this.tooltip,
    required this.confirm,
  });

  final String text;
  final String tooltip;
  final String confirm;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final color = AiTone.muted(context);
    final icon = _copied ? FLucideIcons.check : FLucideIcons.copy;
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: AppTappable(
        onPress: () async {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (!mounted) return;
          setState(() => _copied = true);
          Future<void>.delayed(Motion.copyFeedback, () {
            if (mounted) setState(() => _copied = false);
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Icon(icon, size: AppIconSizes.xs, color: color),
        ),
      ),
    );
  }
}

Widget _selectableRich(List<InlineSpan> spans, {required bool selectable}) {
  final span = TextSpan(children: spans);
  return selectable ? SelectableText.rich(span) : Text.rich(span);
}
