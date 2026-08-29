/// ExecutionOS route path contract.
library;

abstract final class ExecutionRoutes {
  static const today = '/execution';
  static const plans = '/execution/plans';
  static const review = '/execution/review';
  static const actionDetail = '/execution/action/:id';
  static const planDetail = '/execution/plans/:id';

  static String action(String id) =>
      '/execution/action/${Uri.encodeComponent(id)}';

  static String plan(String id) =>
      '/execution/plans/${Uri.encodeComponent(id)}';
}

abstract final class ExecutionRouteNames {
  static const today = 'execution-today';
  static const plans = 'execution-plans';
  static const review = 'execution-review';
  static const actionDetail = 'execution-action-detail';
  static const planDetail = 'execution-plan-detail';
}
