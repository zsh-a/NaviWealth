part of 'ai_markdown.dart';

sealed class _MdBlock {
  const _MdBlock();

  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  });
}

class _MdParagraph extends _MdBlock {
  const _MdParagraph(this.text);

  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final spans = _InlineParser.parse(text, base, context);
    if (trailing != null) spans.add(trailing);
    return _selectableRich(spans, selectable: selectable);
  }
}

class _MdHeading extends _MdBlock {
  const _MdHeading(this.level, this.text);

  final int level;
  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final style = AiType.heading(context, base, level);
    final spans = _InlineParser.parse(text, style, context);
    if (trailing != null) spans.add(trailing);
    return Semantics(
      header: true,
      child: _selectableRich(spans, selectable: selectable),
    );
  }
}

class _MdHr extends _MdBlock {
  const _MdHr();

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Container(
        height: AppStroke.hairline,
        color: AiTone.outline(context),
      ),
    );
  }
}

class _MdQuote extends _MdBlock {
  const _MdQuote(this.text);

  final String text;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final style = base.copyWith(
      color: AiTone.muted(context),
      fontStyle: FontStyle.italic,
    );
    final spans = _InlineParser.parse(text, style, context);
    if (trailing != null) spans.add(trailing);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AiTone.outline(context),
            width: AppStroke.accent,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: AppSpacing.s8),
      child: _selectableRich(spans, selectable: selectable),
    );
  }
}

class _MdListItem {
  const _MdListItem(this.text, this.marker, {this.level = 0, this.checkbox});

  final String text;
  final String? marker;
  final int level;
  final bool? checkbox;
}

class _MdList extends _MdBlock {
  const _MdList(this.items);

  final List<_MdListItem> items;

  @override
  Widget build(
    BuildContext context, {
    required TextStyle base,
    required InlineSpan? trailing,
    required bool selectable,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final isLast = i == items.length - 1;
      final item = items[i];
      final lineStyle = item.checkbox == true
          ? base.copyWith(
              color: AiTone.muted(context),
              decoration: TextDecoration.lineThrough,
            )
          : base;
      final spans = _InlineParser.parse(item.text, lineStyle, context);
      if (isLast && trailing != null) spans.add(trailing);
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: item.level * AppSpacing.s16,
            bottom: isLast ? 0 : AppSpacing.s2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _marker(context, base, item),
              Expanded(child: _selectableRich(spans, selectable: selectable)),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _marker(BuildContext context, TextStyle base, _MdListItem item) {
    if (item.checkbox != null) {
      final box = Padding(
        padding: const EdgeInsets.only(
          right: AppSpacing.s8,
          top: AppSpacing.s2,
        ),
        child: _TaskCheckbox(checked: item.checkbox!),
      );
      final marker = item.marker;
      if (marker != null) {
        final style = base.copyWith(color: AiTone.muted(context));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: SizedBox(
                width: AppControlWidths.markdownMarker,
                child: Text(marker, style: style, textAlign: TextAlign.right),
              ),
            ),
            box,
          ],
        );
      }
      return box;
    }
    final style = base.copyWith(color: AiTone.muted(context));
    if (item.marker != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s8),
        child: SizedBox(
          width: AppControlWidths.markdownMarker,
          child: Text(item.marker!, style: style, textAlign: TextAlign.right),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        right: AppSpacing.s8,
        top: AppSpacing.s6,
      ),
      child: Container(
        width: AppStroke.indicator,
        height: AppStroke.indicator,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AiTone.muted(context),
        ),
      ),
    );
  }
}

class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: checked ? AiTone.active(context) : Colors.transparent,
        border: Border.all(
          color: checked ? AiTone.active(context) : AiTone.outline(context),
          width: AppStroke.thin,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
      child: checked
          ? Icon(
              FLucideIcons.check,
              size: 10,
              color: context.theme.colors.primaryForeground,
            )
          : null,
    );
  }
}
