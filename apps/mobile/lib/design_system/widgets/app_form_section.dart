import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_icon_tile.dart';

/// Groups related fields inside a form page.
///
/// - [AppFormSection.new] — flat column with a uniform [gap] between
///   children and an optional caption-style [title].
/// - [AppFormSection.collapsible] — titled disclosure block (lifted
///   [FAccordion]) whose body stays mounted but is hidden via
///   `Offstage` + `ExcludeFocus` + `ExcludeSemantics` while collapsed,
///   matching the trade-entry advanced-details pattern.
class AppFormSection extends StatelessWidget {
  const AppFormSection({
    super.key,
    this.title,
    required this.children,
    this.gap = AppSpacing.s12,
  }) : icon = null,
       summary = null,
       itemKey = null,
       titleKey = null,
       detailsKey = null,
       expanded = null,
       onChanged = null,
       focusNode = null;

  const AppFormSection.collapsible({
    super.key,
    required this.title,
    this.icon,
    this.summary,
    this.itemKey,
    this.titleKey,
    this.detailsKey,
    required this.expanded,
    required this.onChanged,
    this.focusNode,
    required this.children,
    this.gap = AppSpacing.s12,
  });

  final String? title;
  final IconData? icon;
  final String? summary;

  /// Key forwarded to the collapsible `FAccordionItem`.
  final Key? itemKey;

  /// Key forwarded to the collapsible title `Semantics` node.
  final Key? titleKey;

  /// Key forwarded to the collapsible body `Offstage`.
  final Key? detailsKey;
  final bool? expanded;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;
  final List<Widget> children;
  final double gap;

  bool get _isCollapsible => expanded != null;

  List<Widget> _gappedChildren() {
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsible) {
      return _buildCollapsible(context);
    }
    final title = this.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: context.captionLabelStyle.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        ..._gappedChildren(),
      ],
    );
  }

  Widget _buildCollapsible(BuildContext context) {
    final expanded = this.expanded!;
    final onChanged = this.onChanged!;
    return FAccordion(
      control: FAccordionControl.lifted(
        expanded: (_) => expanded,
        onChange: (_, value) => onChanged(value),
      ),
      children: [
        FAccordionItem(
          key: itemKey,
          focusNode: focusNode,
          title: _DisclosureTitle(
            titleKey: titleKey,
            icon: icon,
            title: title!,
            summary: summary,
            expanded: expanded,
          ),
          child: Offstage(
            key: detailsKey,
            offstage: !expanded,
            child: ExcludeFocus(
              excluding: !expanded,
              child: ExcludeSemantics(
                excluding: !expanded,
                child: Column(children: _gappedChildren()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Accordion header row mirroring the trade-entry disclosure title:
/// optional tinted icon tile, label, and muted summary caption.
class _DisclosureTitle extends StatelessWidget {
  const _DisclosureTitle({
    required this.titleKey,
    required this.icon,
    required this.title,
    required this.summary,
    required this.expanded,
  });

  final Key? titleKey;
  final IconData? icon;
  final String title;
  final String? summary;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final summary = this.summary;
    return Semantics(
      key: titleKey,
      expanded: expanded,
      child: Row(
        children: [
          if (icon != null) ...[
            AppIconTile(icon: icon, color: context.theme.colors.primary),
            const SizedBox(width: AppSpacing.s10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                if (summary != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(summary, style: context.captionStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
