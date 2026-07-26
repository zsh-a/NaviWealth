import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_providers.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/features/finance/shared/ui/account_color.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'expense_category_l10n.dart';
import 'expense_category_picker.dart';
import 'expense_category_visuals.dart';

class ExpenseCategoriesPage extends ConsumerWidget {
  const ExpenseCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(allExpenseCategoriesProvider);
    return AppPageScaffold(
      title: l10n.expenseCategoriesManageTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.expenseCategoriesAdd,
          icon: const Icon(FLucideIcons.plus),
          onPress: categoriesAsync.hasValue
              ? () => _showCategorySheet(
                  context,
                  ref,
                  categories: categoriesAsync.requireValue,
                )
              : null,
        ),
      ],
      childPad: false,
      child: categoriesAsync.whenOrLoading(
        context: context,
        onRetry: () => ref.invalidate(allExpenseCategoriesProvider),
        data: (categories) => _CategoryList(categories: categories),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories});

  final List<ExpenseCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ordered = _orderedCategories(categories);
    if (ordered.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.tags,
        title: l10n.expenseCategoriesEmpty,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s6),
      itemBuilder: (context, index) {
        final item = ordered[index];
        final category = item.category;
        final siblings = ordered
            .map((entry) => entry.category)
            .where((entry) => entry.parentId == category.parentId)
            .toList(growable: false);
        final siblingIndex = siblings.indexWhere(
          (entry) => entry.id == category.id,
        );
        return Opacity(
          opacity: category.archived ? 0.55 : 1,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: item.depth * AppSpacing.s16,
            ),
            child: SoftCard.flat(
              child: FTappable(
                onPress: () => _showCategorySheet(
                  context,
                  ref,
                  categories: categories,
                  category: category,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: category
                              .expenseAccentColor(context, ordinal: index)
                              .withValues(alpha: AppOpacity.subtle),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          category.iconData,
                          size: AppIconSizes.h18,
                          color: category.expenseAccentColor(
                            context,
                            ordinal: index,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizedExpenseCategoryName(l10n, category),
                              style: context.labelStyle,
                            ),
                            Text(
                              category.archived
                                  ? l10n.expenseCategoriesArchived
                                  : category.isBuiltIn
                                  ? l10n.expenseCategoriesBuiltIn
                                  : l10n.expenseCategoriesCustom,
                              style: context.captionStyle,
                            ),
                          ],
                        ),
                      ),
                      AppIconButton(
                        tooltip: l10n.expenseCategoriesMoveUp,
                        icon: FLucideIcons.chevronUp,
                        onPress: siblingIndex <= 0
                            ? null
                            : () => _move(
                                ref,
                                category,
                                siblings[siblingIndex - 1],
                              ),
                      ),
                      AppIconButton(
                        tooltip: l10n.expenseCategoriesMoveDown,
                        icon: FLucideIcons.chevronDown,
                        onPress:
                            siblingIndex < 0 ||
                                siblingIndex >= siblings.length - 1
                            ? null
                            : () => _move(
                                ref,
                                category,
                                siblings[siblingIndex + 1],
                              ),
                      ),
                      Icon(
                        FLucideIcons.pencil,
                        size: AppIconSizes.sm,
                        color: context.theme.colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _move(
    WidgetRef ref,
    ExpenseCategory current,
    ExpenseCategory other,
  ) async {
    final repository = await ref.read(expenseCategoryRepositoryProvider.future);
    await repository.setSortOrder(current.id, other.sortOrder);
    await repository.setSortOrder(other.id, current.sortOrder);
  }
}

Future<void> _showCategorySheet(
  BuildContext context,
  WidgetRef ref, {
  required List<ExpenseCategory> categories,
  ExpenseCategory? category,
}) async {
  await showAppFormSheet<void>(
    context: context,
    builder: (_) => _CategoryFormSheet(
      ref: ref,
      categories: categories,
      category: category,
    ),
  );
}

class _CategoryFormSheet extends StatefulWidget {
  const _CategoryFormSheet({
    required this.ref,
    required this.categories,
    this.category,
  });

  final WidgetRef ref;
  final List<ExpenseCategory> categories;
  final ExpenseCategory? category;

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late final TextEditingController _nameController;
  late String _icon;
  String? _color;
  String? _parentId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(
      text: category?.nameOverride ?? category?.name ?? '',
    );
    _icon = category?.icon ?? 'category';
    _color = category?.color;
    _parentId = category?.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.category != null;
    return AppSheet(
      title: editing ? l10n.expenseCategoriesEdit : l10n.expenseCategoriesAdd,
      actions: [
        if (editing)
          AppIconButton(
            tooltip: widget.category!.archived
                ? l10n.expenseCategoriesRestore
                : l10n.expenseCategoriesArchive,
            icon: widget.category!.archived
                ? FLucideIcons.archiveRestore
                : FLucideIcons.archive,
            onPress: _saving ? null : _toggleArchived,
          ),
      ],
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _nameController),
            label: Text(l10n.expenseCategoriesNameLabel),
          ),
          const SizedBox(height: AppSpacing.s12),
          ExpenseCategoryPicker(
            categories: widget.categories,
            value: _parentId,
            onChanged: (value) => setState(() => _parentId = value),
            label: l10n.expenseCategoriesParentLabel,
            helperText: l10n.expenseCategoriesParentHelper,
            leafOnly: false,
            excludeIds: {if (widget.category != null) widget.category!.id},
            validator: (_) => null,
          ),
          if (_parentId != null) ...[
            const SizedBox(height: AppSpacing.s6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FButton(
                variant: FButtonVariant.ghost,
                onPress: () => setState(() => _parentId = null),
                child: Text(l10n.expenseCategoriesMakeTopLevel),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Text(l10n.expenseCategoriesIconLabel, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final token in _editableIconTokens)
                _IconChoice(
                  token: token,
                  selected: token == _icon,
                  onTap: () => setState(() => _icon = token),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(l10n.expenseCategoriesColorLabel, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.expenseCategoriesColorHelper, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s10,
            runSpacing: AppSpacing.s10,
            children: [
              for (final hex in _editableColorHexes)
                _ColorChoice(
                  hex: hex,
                  selected: hex == _color,
                  onTap: () => setState(() => _color = hex),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context).expenseCategoriesNameRequired;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await widget.ref.read(
        expenseCategoryRepositoryProvider.future,
      );
      final category = widget.category;
      if (category == null) {
        await repository.create(
          name: name,
          parentId: _parentId,
          icon: _icon,
          color: _color,
        );
      } else {
        await repository.update(
          id: category.id,
          name: name,
          parentId: _parentId,
          icon: _icon,
          color: _color,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userSafeErrorMessage(context, error);
        });
      }
    }
  }

  Future<void> _toggleArchived() async {
    final category = widget.category;
    if (category == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await widget.ref.read(
        expenseCategoryRepositoryProvider.future,
      );
      await repository.setArchived(category.id, archived: !category.archived);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userSafeErrorMessage(context, error);
        });
      }
    }
  }
}

const _editableIconTokens = <String>[
  'category',
  'restaurant',
  'local_grocery_store',
  'local_cafe',
  'directions_bus',
  'local_taxi',
  'home',
  'shopping_bag',
  'sports_esports',
  'medical_services',
  'school',
  'flight',
  'card_giftcard',
  'pets',
  'fitness_center',
  'receipt_long',
];

const _editableColorHexes = <String>[
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#84CC16',
  '#10B981',
  '#17A8B0',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#D946EF',
  '#EC4899',
];

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.token,
    required this.selected,
    required this.onTap,
  });

  final String token;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: token,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.subtle)
                : colors.muted.withValues(alpha: AppOpacity.subtle),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            kExpenseCategoryIcons[token] ?? kExpenseCategoryFallbackIcon,
            size: AppIconSizes.h18,
            color: selected ? colors.primary : colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = parseAccountColor(hex)!;
    return Semantics(
      button: true,
      selected: selected,
      label: hex,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(AppSpacing.accentBar),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? context.theme.colors.foreground
                  : context.theme.colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

List<({ExpenseCategory category, int depth})> _orderedCategories(
  List<ExpenseCategory> categories,
) {
  final byParent = <String?, List<ExpenseCategory>>{};
  for (final category in categories) {
    byParent.putIfAbsent(category.parentId, () => []).add(category);
  }
  for (final children in byParent.values) {
    children.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.name.compareTo(b.name);
    });
  }
  final result = <({ExpenseCategory category, int depth})>[];
  final visited = <String>{};
  void addBranch(String? parentId, int depth) {
    for (final category in byParent[parentId] ?? const <ExpenseCategory>[]) {
      if (!visited.add(category.id)) continue;
      result.add((category: category, depth: depth));
      addBranch(category.id, depth + 1);
    }
  }

  addBranch(null, 0);
  for (final category in categories) {
    if (visited.add(category.id)) {
      result.add((category: category, depth: 0));
    }
  }
  return result;
}
