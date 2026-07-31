import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef EntityRouteResolver = String? Function(EntityRouteRef ref);
typedef SourceRouteResolver =
    String? Function(String sourceRowFamily, String sourceRowId);

/// Domain-neutral reference to a persisted entity that may have an app route.
///
/// Feature surfaces such as AI evidence chips should emit this stable table/id
/// pair and let the app composition root decide which active domain owns the
/// final deep link.
class EntityRouteRef {
  const EntityRouteRef({required this.entityTable, required this.entityId});

  final String entityTable;
  final String entityId;
}

abstract final class EntityRouteTables {
  static const assets = 'assets';
  static const accounts = 'accounts';
  static const liabilities = 'liabilities';
  static const journalEntries = 'journal_entries';
  static const optionsTradeJournal = 'options_trade_journal';
  static const optionsLeapsCallPositions = 'options_leaps_call_positions';
  static const incomeStrategyPlans = 'income_strategy_plans';
}

final entityRouteResolverProvider = Provider<EntityRouteResolver>(
  (_) =>
      (_) => null,
);

/// Resolves ExecutionOS source metadata, including aggregate identities that
/// are not real table row ids.
final sourceRouteResolverProvider = Provider<SourceRouteResolver>(
  (_) =>
      (_, _) => null,
);
