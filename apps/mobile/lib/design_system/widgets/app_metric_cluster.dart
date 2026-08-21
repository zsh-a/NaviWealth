import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import '../tokens/typography_tokens.dart';
import 'amount_privacy_placeholder.dart';
import 'amount_privacy_scope.dart';
import 'app_divider.dart';

/// One flat metric cell inside a parent surface — never a nested card.
class AppMetricItem {
  const AppMetricItem({
    required this.label,
    required this.value,
    this.flex = 1,
    this.maxLines = 2,
    this.sensitive = false,
  });

  final String label;
  final String value;
  final int flex;
  final int maxLines;

  /// Whether [value] contains an exact monetary amount that should respect
  /// the nearest [AmountPrivacyScope].
  final bool sensitive;
}

/// Divider-separated metric cluster for hero / raised modules.
///
/// Prefer this over nested [SoftCard] / rounded inset boxes so each page keeps
/// a single surface hierarchy: one outer card, flat internal partitions.
class AppMetricCluster extends StatelessWidget {
  const AppMetricCluster({
    super.key,
    required this.items,
    this.axis = Axis.horizontal,
    this.dense = false,
  });

  final List<AppMetricItem> items;
  final Axis axis;

  /// Tighter vertical padding for dense hubs.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.theme.colors;
    final gap = dense ? AppPageRhythm.row : AppSpacing.s10;

    if (axis == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              SizedBox(height: gap),
              const AppDivider(horizontalPadding: 0),
              SizedBox(height: gap),
            ],
            _MetricCell(item: items[i], dense: dense),
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: AppStroke.hairline,
                margin: EdgeInsets.symmetric(
                  horizontal: dense ? AppSpacing.s10 : AppSpacing.s14,
                  vertical: AppSpacing.s2,
                ),
                color: colors.border.withValues(alpha: AppOpacity.highlight),
              ),
            Expanded(
              flex: items[i].flex,
              child: _MetricCell(item: items[i], dense: dense),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.item, required this.dense});

  final AppMetricItem item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label,
          style: context.captionStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: dense ? AppSpacing.s2 : AppSpacing.s4),
        if (item.sensitive && AmountPrivacyScope.isHiddenOf(context))
          AmountPrivacyPlaceholder(
            density: dense
                ? AmountPrivacyPlaceholderDensity.body
                : AmountPrivacyPlaceholderDensity.title,
            style: dense
                ? TypographyTokens.numericBodyStrong
                : context.labelStyle,
            semanticsLabel: AmountPrivacyScope.hiddenSemanticsLabelOf(context),
          )
        else
          Text(
            item.value,
            style: dense
                ? TypographyTokens.numericBodyStrong
                : context.labelStyle,
            maxLines: item.maxLines,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
