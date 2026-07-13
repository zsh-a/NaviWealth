import 'package:flutter/material.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'soft_card.dart';

/// Canonical section surface with optional title and trailing control.
///
/// - [AppSection.item] — dense nested rows (flat)
/// - [AppSection.group] — titled dashboard modules (raised)
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.padding = AppPageRhythm.cardPadding,
    this.trailing,
    this.onPress,
    this.level = SoftCardLevel.flat,
    this.borderless = false,
  });

  const AppSection.item({
    Key? key,
    String? title,
    List<Widget> children = const <Widget>[],
    Widget? trailing,
    VoidCallback? onPress,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: AppPageRhythm.densePadding,
         trailing: trailing,
         onPress: onPress,
         level: SoftCardLevel.flat,
         borderless: true,
       );

  const AppSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
    VoidCallback? onPress,
    SoftCardLevel level = SoftCardLevel.raised,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: AppPageRhythm.cardPadding,
         trailing: trailing,
         onPress: onPress,
         level: level,
       );

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final EdgeInsets padding;
  final Widget? trailing;
  final VoidCallback? onPress;
  final SoftCardLevel level;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    final t = title;
    return SoftCard(
      onPress: onPress,
      padding: padding,
      level: level,
      borderless: borderless,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    t,
                    style: titleStyle ?? context.rowTitleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.s8),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
          ],
          ...children,
        ],
      ),
    );
  }
}
