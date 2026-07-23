import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'expense_category_l10n.dart';
import 'expense_category_visuals.dart';

class ExpenseCategoryPicker extends StatelessWidget {
  const ExpenseCategoryPicker({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    required this.label,
    this.helperText,
    this.leafOnly = true,
    this.excludeIds = const <String>{},
    this.validator,
  });

  final List<ExpenseCategory> categories;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? helperText;
  final bool leafOnly;
  final Set<String> excludeIds;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byId = <String, ExpenseCategory>{
      for (final category in categories) category.id: category,
    };
    final parentIds = <String>{
      for (final category in categories)
        if (category.parentId != null) category.parentId!,
    };
    final entries =
        categories
            .where(
              (category) =>
                  !category.archived &&
                  category.sync.deletedAt == null &&
                  !category.isMerged &&
                  !excludeIds.contains(category.id) &&
                  (!leafOnly || !parentIds.contains(category.id)),
            )
            .map(
              (category) => (
                category: category,
                path: localizedExpenseCategoryPath(l10n, category, byId),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final order = a.category.sortOrder.compareTo(b.category.sortOrder);
            return order != 0 ? order : a.path.compareTo(b.path);
          });
    final effectiveValue = entries.any((entry) => entry.category.id == value)
        ? value
        : null;
    final pathById = <String, String>{
      for (final entry in entries) entry.category.id: entry.path,
    };
    return FSelect<String>.rich(
      format: (id) => pathById[id] ?? '',
      control: FSelectControl<String>.lifted(
        value: effectiveValue,
        onChange: onChanged,
      ),
      label: Text(label),
      description: helperText == null ? null : Text(helperText!),
      enabled: entries.isNotEmpty,
      validator: validator ?? FFormFieldProperties.defaultValidator,
      children: [
        for (final entry in entries)
          FSelectItem<String>(
            value: entry.category.id,
            title: Text(entry.path, maxLines: 2, overflow: TextOverflow.fade),
            prefix: Icon(
              entry.category.iconData,
              size: AppIconSizes.sm,
              color:
                  entry.category.accentColor ??
                  context.theme.colors.mutedForeground,
            ),
          ),
      ],
    );
  }
}
