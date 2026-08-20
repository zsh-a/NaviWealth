import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_grouped_action_list.dart';
import 'app_overlay_surface.dart';
import 'app_sheet.dart';
import 'app_tappable.dart';

typedef AppAdaptiveSelectionTriggerBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback openMenu,
      FocusNode focusNode,
    );

/// One value shown by [AppAdaptiveSelectionMenu].
class AppAdaptiveSelection<T> {
  const AppAdaptiveSelection({
    required this.value,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;
}

/// A single-choice menu that follows the interaction conventions of the host.
///
/// Pointer-first platforms receive a compact anchored popover. Touch-first
/// platforms receive the same choices in the canonical draggable app sheet.
/// The selected value is always explicit, so this works for page-level scope
/// switchers without making them look like form fields.
class AppAdaptiveSelectionMenu<T> extends StatefulWidget {
  const AppAdaptiveSelectionMenu({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.triggerBuilder,
    this.subtitle,
  }) : assert(options.length > 0, 'At least one option is required.');

  final String title;
  final String? subtitle;
  final List<AppAdaptiveSelection<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final AppAdaptiveSelectionTriggerBuilder triggerBuilder;

  @override
  State<AppAdaptiveSelectionMenu<T>> createState() =>
      _AppAdaptiveSelectionMenuState<T>();
}

class _AppAdaptiveSelectionMenuState<T>
    extends State<AppAdaptiveSelectionMenu<T>>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _popover;
  final FocusNode _triggerFocus = FocusNode(
    debugLabel: 'adaptive selection menu trigger',
  );

  @override
  void initState() {
    super.initState();
    _popover = FPopoverController(vsync: this);
  }

  @override
  void dispose() {
    _popover.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  bool get _usesAnchoredMenu {
    return switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FPopover(
      control: FPopoverControl.managed(controller: _popover),
      popoverAnchor: AlignmentDirectional.topStart,
      childAnchor: AlignmentDirectional.bottomStart,
      constraints: kAppPopoverSelectionConstraints,
      popoverBuilder: (context, _) => SingleChildScrollView(
        key: const ValueKey<String>('app-adaptive-selection-menu.popover'),
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: _SelectionList<T>(
          options: widget.options,
          value: widget.value,
          onSelected: _selectAnchored,
        ),
      ),
      child: widget.triggerBuilder(context, _openMenu, _triggerFocus),
    );
  }

  void _openMenu() {
    if (_usesAnchoredMenu) {
      _popover.toggle();
      return;
    }
    unawaited(_showTouchMenu());
  }

  Future<void> _selectAnchored(T value) async {
    await _popover.hide();
    if (!mounted) return;
    _triggerFocus.requestFocus();
    if (value != widget.value) widget.onChanged(value);
  }

  Future<void> _showTouchMenu() async {
    final selected = await showAppSheet<T>(
      context: context,
      title: widget.title,
      subtitle: widget.subtitle,
      builder: (sheetContext) => _SelectionList<T>(
        options: widget.options,
        value: widget.value,
        onSelected: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (selected == null || !mounted) return;
    _triggerFocus.requestFocus();
    if (selected != widget.value) widget.onChanged(selected);
  }
}

class _SelectionList<T> extends StatelessWidget {
  const _SelectionList({
    required this.options,
    required this.value,
    required this.onSelected,
  });

  final List<AppAdaptiveSelection<T>> options;
  final T value;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < options.length; index++) ...[
          _SelectionRow<T>(
            option: options[index],
            selected: options[index].value == value,
            onPress: () => onSelected(options[index].value),
          ),
          if (index != options.length - 1)
            const AppGroupedDivider(
              indent: AppSpacing.s12,
              endIndent: AppSpacing.s12,
            ),
        ],
      ],
    );
  }
}

class _SelectionRow<T> extends StatelessWidget {
  const _SelectionRow({
    required this.option,
    required this.selected,
    required this.onPress,
  });

  final AppAdaptiveSelection<T> option;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final subtitle = option.subtitle;
    final hasSubtitle = subtitle != null && subtitle.isNotEmpty;
    return Semantics(
      button: true,
      selected: selected,
      label: option.title,
      child: AppTappable(
        selected: selected,
        onPress: onPress,
        child: AppHoverFill(
          selected: selected,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: hasSubtitle ? AppSpacing.s10 : AppSpacing.s12,
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.s28,
                  height: AppSpacing.s28,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: AppOpacity.faint),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    option.icon,
                    size: AppIconSizes.sm,
                    color: selected ? colors.primary : colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.labelStyle.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.captionStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                SizedBox.square(
                  dimension: AppIconSizes.sm,
                  child: selected
                      ? Icon(
                          FLucideIcons.check,
                          size: AppIconSizes.sm,
                          color: colors.primary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
