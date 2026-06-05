import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'soft_card.dart';

/// Canonical section surface with optional title and trailing control.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.trailing,
    this.onPress,
    this.level = SoftCardLevel.flat,
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
         padding: const EdgeInsets.all(AppSpacing.s12),
         trailing: trailing,
         onPress: onPress,
       );

  const AppSection.group({
    Key? key,
    required String title,
    required List<Widget> children,
    Widget? trailing,
    VoidCallback? onPress,
    SoftCardLevel level = SoftCardLevel.flat,
  }) : this(
         key: key,
         title: title,
         children: children,
         padding: const EdgeInsets.all(AppSpacing.s16),
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

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final t = title;
    return SoftCard(
      onPress: onPress,
      padding: padding,
      level: level,
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
                    style:
                        titleStyle ??
                        typography.md.copyWith(fontWeight: FontWeight.w600),
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
            const SizedBox(height: AppSpacing.s8),
          ],
          ...children,
        ],
      ),
    );
  }
}
