import 'package:naviwealth/core/sync/sync_meta.dart';

/// Identity and ownership boundary for a logical investment portfolio.
///
/// Goals answer "why", strategy modules answer "how", and rebalance groups
/// own capital policy. Keeping those concerns out of this entity lets a
/// portfolio compose several independent strategies without nullable fields
/// or a closed portfolio-type enum.
class InvestmentPortfolio {
  const InvestmentPortfolio({
    required this.id,
    required this.name,
    required this.baseCurrency,
    required this.goalId,
    required this.color,
    required this.createdAt,
    required this.archived,
    required this.sync,
  });

  final String id;
  final String name;
  final String? baseCurrency;
  final String? goalId;
  final String? color;
  final DateTime createdAt;
  final bool archived;
  final SyncMeta sync;

  InvestmentPortfolio copyWith({
    String? name,
    String? baseCurrency,
    String? goalId,
    String? color,
    bool? archived,
    SyncMeta? sync,
  }) {
    return InvestmentPortfolio(
      id: id,
      name: name ?? this.name,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      goalId: goalId ?? this.goalId,
      color: color ?? this.color,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      sync: sync ?? this.sync,
    );
  }
}
