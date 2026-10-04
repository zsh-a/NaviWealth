part of '../ingest_review_page.dart';

const _clearCategoryValue = '__clear_category__';

String _reviewCategoryDisplay(AppLocalizations l10n, ParsedTransaction parsed) {
  if (parsed.kind != IngestTransactionKind.expense &&
      parsed.kind != IngestTransactionKind.income) {
    return parsed.categoryHint ?? l10n.ingestUncategorized;
  }
  final value = _canonicalReviewCategory(parsed.kind, parsed.categoryHint);
  final options = _reviewCategoryOptions(l10n, parsed.kind);
  if (value == null) return l10n.ingestUncategorized;
  return options[value] ?? l10n.ingestCategoryFallback(value);
}

String? _canonicalReviewCategory(IngestTransactionKind kind, String? hint) {
  if (hint == null || hint.isEmpty) return null;
  if (kind == IngestTransactionKind.expense) {
    return expenseCategoryByInput(hint)?.slug ?? hint;
  }
  return hint;
}

Map<String, String> _reviewCategoryOptions(
  AppLocalizations l10n,
  IngestTransactionKind kind,
) => kind == IngestTransactionKind.expense
    ? {
        for (final category in kExpenseCategoryTaxonomy)
          category.slug: () {
            final preset = expenseCategoryPresetByKey(category.slug);
            return l10n.localeName.startsWith('zh')
                ? category.labelZh
                : preset?.nameEn ?? category.slug;
          }(),
      }
    : {
        'salary': l10n.ingestCategorySalary,
        'dividend': l10n.ingestCategoryDividend,
        'interest': l10n.ingestCategoryInterest,
        'other': l10n.entryKindOther,
      };

bool _supportsReviewCategory(IngestTransactionKind kind, String? value) =>
    value == null ||
    (kind == IngestTransactionKind.expense
        ? isExpenseCategorySlug(value)
        : const {'salary', 'dividend', 'interest', 'other'}.contains(value));

class _IngestCategoryPicker extends StatelessWidget {
  const _IngestCategoryPicker({
    required this.kind,
    required this.value,
    required this.onChanged,
    this.label,
    this.unchanged = false,
  });

  final IngestTransactionKind kind;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final bool unchanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = _reviewCategoryOptions(l10n, kind);
    final unsupported = value != null && !options.containsKey(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FSelect<String>.rich(
          key: ValueKey('ingest-category-${kind.name}'),
          label: Text(label ?? l10n.ingestEditCategory),
          description: Text(l10n.ingestCategoryAppliedHint),
          format: (value) => value == _clearCategoryValue
              ? l10n.ingestCategoryUncategorized
              : options[value] ?? value,
          hint: l10n.ingestCategoryUnchanged,
          control: FSelectControl<String>.lifted(
            value: unchanged ? null : value ?? _clearCategoryValue,
            onChange: (value) {
              if (value == null) return;
              onChanged(value == _clearCategoryValue ? null : value);
            },
          ),
          children: [
            FSelectItem(
              value: _clearCategoryValue,
              title: Text(l10n.ingestCategoryUncategorized),
            ),
            if (unsupported) FSelectItem(value: value!, title: Text(value!)),
            for (final entry in options.entries)
              FSelectItem(value: entry.key, title: Text(entry.value)),
          ],
        ),
        if (unsupported) ...[
          const SizedBox(height: AppSpacing.s8),
          AppStatusBanner(
            kind: AppStatusKind.warning,
            message: l10n.ingestCategoryUnsupported,
          ),
        ],
      ],
    );
  }
}
