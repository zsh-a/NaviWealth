part of 'target_allocation_editor_sheet.dart';

class _AssetTargetDraft {
  const _AssetTargetDraft({
    required this.assetId,
    required this.label,
    required this.category,
    required this.weight,
  });

  final String assetId;
  final String label;
  final AssetCategory category;
  final double weight;

  _AssetTargetDraft copyWith({double? weight}) => _AssetTargetDraft(
    assetId: assetId,
    label: label,
    category: category,
    weight: weight ?? this.weight,
  );
}

class _AssetOption {
  const _AssetOption({
    required this.assetId,
    required this.label,
    required this.category,
  });

  final String assetId;
  final String label;
  final AssetCategory category;
}

List<_AssetOption> _assetOptions(DashboardSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final options = <_AssetOption>[];
  for (final allocation in snapshot.allocations) {
    if (allocation.isLiability) continue;
    for (final item in allocation.items) {
      options.add(
        _AssetOption(
          assetId: item.id,
          label: item.name,
          category: allocation.category,
        ),
      );
    }
  }
  options.sort((a, b) => a.label.compareTo(b.label));
  return options;
}
