import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_presets.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

String localizedExpenseCategoryName(
  AppLocalizations l10n,
  ExpenseCategory category,
) {
  final override = category.nameOverride?.trim();
  if (override != null && override.isNotEmpty) return override;
  final systemKey = category.systemKey;
  final preset = systemKey == null
      ? null
      : expenseCategoryPresetByKey(systemKey);
  if (preset == null) return category.name;
  return l10n.localeName.startsWith('zh') ? preset.nameZh : preset.nameEn;
}

String localizedExpenseCategoryPath(
  AppLocalizations l10n,
  ExpenseCategory category,
  Map<String, ExpenseCategory> byId,
) {
  final segments = <String>[];
  ExpenseCategory? cursor = category;
  final visited = <String>{};
  while (cursor != null && visited.add(cursor.id)) {
    segments.add(localizedExpenseCategoryName(l10n, cursor));
    cursor = cursor.parentId == null ? null : byId[cursor.parentId];
  }
  return segments.reversed.join(' / ');
}
