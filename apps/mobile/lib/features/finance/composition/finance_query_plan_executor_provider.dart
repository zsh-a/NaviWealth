import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_tools/query_plan/query_plan_executor.dart';

/// Executor seam for the command palette's inline finance query result.
///
/// FinanceOS overrides this with its Drift-backed adapter. The default keeps
/// reduced-domain tests usable without a database.
final financeQueryPlanExecutorProvider = Provider<QueryPlanExecutor>(
  (ref) => InMemoryQueryPlanExecutor(transactions: const []),
);
