import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_action_sheet_tile.dart';
import 'app_sheet.dart';

typedef AppAdaptiveActionCallback = FutureOr<void> Function();

typedef AppAdaptiveActionTriggerBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback openMenu,
      FocusNode focusNode,
    );

/// One command shown by [AppAdaptiveActionMenu].
class AppAdaptiveAction {
  const AppAdaptiveAction({
    required this.icon,
    required this.title,
    required this.onPress,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final AppAdaptiveActionCallback onPress;
  final bool destructive;
}

/// A short action menu that follows the interaction conventions of the host.
///
/// Pointer-first platforms receive a compact popover anchored to [triggerBuilder].
/// Touch-first platforms receive the same actions in the canonical bottom sheet.
/// Forms, filters and multi-step pickers should continue to use [showAppSheet]
/// directly instead of this command-menu primitive.
class AppAdaptiveActionMenu extends StatefulWidget {
  const AppAdaptiveActionMenu({
    super.key,
    required this.title,
    required this.actions,
    required this.triggerBuilder,
    this.subtitle,
  }) : assert(actions.length > 0, 'At least one action is required.');

  final String title;
  final String? subtitle;
  final List<AppAdaptiveAction> actions;
  final AppAdaptiveActionTriggerBuilder triggerBuilder;

  @override
  State<AppAdaptiveActionMenu> createState() => _AppAdaptiveActionMenuState();
}

class _AppAdaptiveActionMenuState extends State<AppAdaptiveActionMenu>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _popover;
  final FocusNode _triggerFocus = FocusNode(
    debugLabel: 'adaptive action menu trigger',
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
      popoverAnchor: AlignmentDirectional.topEnd,
      childAnchor: AlignmentDirectional.bottomEnd,
      constraints: const FPortalConstraints(
        minWidth: 208,
        maxWidth: 280,
        maxHeight: 360,
      ),
      popoverBuilder: (context, _) => _AnchoredActionMenu(
        actions: widget.actions,
        onSelected: _selectAnchoredAction,
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

  Future<void> _selectAnchoredAction(AppAdaptiveAction action) async {
    await _popover.hide();
    if (!mounted) return;
    _triggerFocus.requestFocus();
    await action.onPress();
  }

  Future<void> _showTouchMenu() async {
    final selected = await showAppSheet<AppAdaptiveAction>(
      context: context,
      title: widget.title,
      subtitle: widget.subtitle,
      builder: (sheetContext) => AppActionSheetList(
        children: <AppActionSheetTile>[
          for (final action in widget.actions)
            AppActionSheetTile(
              icon: action.icon,
              title: action.title,
              subtitle: action.subtitle,
              destructive: action.destructive,
              onPress: () => Navigator.of(sheetContext).pop(action),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _triggerFocus.requestFocus();
    await selected.onPress();
  }
}

class _AnchoredActionMenu extends StatelessWidget {
  const _AnchoredActionMenu({required this.actions, required this.onSelected});

  final List<AppAdaptiveAction> actions;
  final ValueChanged<AppAdaptiveAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SingleChildScrollView(
      key: const ValueKey<String>('app-adaptive-action-menu.popover'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in actions)
            Semantics(
              button: true,
              label: action.title,
              child: FTappable(
                onPress: () => onSelected(action),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        action.icon,
                        size: AppIconSizes.h18,
                        color: action.destructive
                            ? colors.destructive
                            : colors.mutedForeground,
                      ),
                      const SizedBox(width: AppSpacing.s10),
                      Expanded(
                        child: Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.mediumLabelStyle.copyWith(
                            color: action.destructive
                                ? colors.destructive
                                : colors.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
