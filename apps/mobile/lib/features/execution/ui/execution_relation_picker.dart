import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';

const String kExecutionPickerNone = '__none__';

String executionPlanPickerLabel(
  AppLocalizations l10n,
  List<ExecutionPlan> plans,
  String? planId,
) {
  if (planId == null || planId.isEmpty) return l10n.executionNoRelation;
  for (final plan in plans) {
    if (plan.id == planId) return plan.title;
  }
  return l10n.executionUnknownPlan;
}

Future<String?> showExecutionPlanPicker({
  required BuildContext context,
  required List<ExecutionPlan> plans,
  required String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return _showPicker(
    context: context,
    title: l10n.executionPlanField,
    selectedId: selectedId,
    clearLabel: l10n.executionNoRelation,
    emptyTitle: l10n.executionNoPlansAvailable,
    emptyIcon: FLucideIcons.folderOpen,
    items: [
      for (final plan in plans)
        _PickerItem(
          id: plan.id,
          label: plan.title,
          detail: plan.description,
          icon: FLucideIcons.layers,
        ),
    ],
  );
}

Future<String?> showExecutionActionPicker({
  required BuildContext context,
  required List<ExecutionAction> actions,
  required String? selectedId,
}) {
  final l10n = AppLocalizations.of(context);
  return _showPicker(
    context: context,
    title: l10n.executionActionField,
    selectedId: selectedId,
    clearLabel: l10n.executionNoAction,
    emptyTitle: l10n.executionNoActionsAvailable,
    emptyIcon: FLucideIcons.listTodo,
    items: [
      for (final action in actions)
        _PickerItem(
          id: action.id,
          label: action.title,
          detail: action.note,
          icon: FLucideIcons.listTodo,
        ),
    ],
  );
}

Future<String?> _showPicker({
  required BuildContext context,
  required String title,
  required List<_PickerItem> items,
  required String? selectedId,
  required String clearLabel,
  required IconData emptyIcon,
  required String emptyTitle,
}) {
  return showAppSheet<String>(
    context: context,
    title: title,
    scrollable: false,
    maxHeightFactor: 0.82,
    builder: (_) => _PickerList(
      items: items,
      selectedId: selectedId,
      clearLabel: clearLabel,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
    ),
  );
}

class _PickerList extends StatefulWidget {
  const _PickerList({
    required this.items,
    required this.selectedId,
    required this.clearLabel,
    required this.emptyIcon,
    required this.emptyTitle,
  });

  final List<_PickerItem> items;
  final String? selectedId;
  final String clearLabel;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  State<_PickerList> createState() => _PickerListState();
}

class _PickerListState extends State<_PickerList> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showSearch = widget.items.length > 6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExecutionPickerTile(
          key: const ValueKey('picker:none'),
          icon: FLucideIcons.x,
          title: widget.clearLabel,
          selected: widget.selectedId == null || widget.selectedId!.isEmpty,
          onPress: () => Navigator.of(context).pop(kExecutionPickerNone),
        ),
        const AppDivider(),
        if (showSearch) ...[
          const SizedBox(height: AppSpacing.s8),
          _PickerSearchField(
            controller: _query,
            hint: l10n.executionPickerSearchHint,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _query,
          builder: (context, value, _) {
            final query = value.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? widget.items
                : widget.items
                      .where(
                        (item) =>
                            item.label.toLowerCase().contains(query) ||
                            item.detail.toLowerCase().contains(query),
                      )
                      .toList(growable: false);
            final maxHeight = MediaQuery.sizeOf(context).height * 0.44;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: filtered.isEmpty
                  ? AppEmptyState(
                      icon: widget.emptyIcon,
                      title: widget.emptyTitle,
                    )
                  : ListView(
                      shrinkWrap: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        for (final item in filtered)
                          ExecutionPickerTile(
                            key: ValueKey('picker:${item.id}'),
                            icon: item.icon,
                            title: item.label,
                            subtitle: item.detail.trim().isEmpty
                                ? null
                                : item.detail.trim(),
                            selected: item.id == widget.selectedId,
                            onPress: () => Navigator.of(context).pop(item.id),
                          ),
                      ],
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _PickerSearchField extends StatelessWidget {
  const _PickerSearchField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return FTextField(
      control: FTextFieldControl.managed(controller: controller),
      textInputAction: TextInputAction.search,
      maxLines: 1,
      prefixBuilder: (_, _, _) => const Padding(
        padding: EdgeInsetsDirectional.only(
          start: AppSpacing.s12,
          end: AppSpacing.s8,
        ),
        child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
      ),
      hint: hint,
    );
  }
}

class ExecutionPickerTile extends StatelessWidget {
  const ExecutionPickerTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onPress,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTile(
      prefix: Icon(icon, color: selected ? colors.primary : null),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      suffix: selected
          ? Icon(FLucideIcons.check, color: colors.primary)
          : const Icon(FLucideIcons.chevronRight),
      onPress: onPress,
    );
  }
}

class _PickerItem {
  const _PickerItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final String id;
  final String label;
  final String detail;
  final IconData icon;
}
