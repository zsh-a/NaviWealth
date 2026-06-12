import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/local/skills/query_plan_executor.dart';

/// Executor seam for the command palette's inline finance query result.
///
/// FinanceOS overrides this with its Drift-backed adapter. The default keeps
/// the command palette usable in reduced-domain tests and avoids importing
/// Finance repositories from `core/`.
final queryPlanExecutorProvider = Provider<QueryPlanExecutor>(
  (ref) => InMemoryQueryPlanExecutor(transactions: const []),
);
