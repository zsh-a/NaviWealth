/// ExecutionOS route path contract.
library;

abstract final class ExecutionRoutes {
  static const today = '/execution';
  static const commitments = '/execution/commitments';
  static const review = '/execution/review';
  static const actionDetail = '/execution/action/:id';
  static const commitmentDetail = '/execution/commitments/:id';
  static const projectDetail = '/execution/commitments/projects/:id';

  static String action(String id) =>
      '/execution/action/${Uri.encodeComponent(id)}';

  static String commitment(String id) =>
      '/execution/commitments/${Uri.encodeComponent(id)}';

  static String project(String id) =>
      '/execution/commitments/projects/${Uri.encodeComponent(id)}';
}

abstract final class ExecutionRouteNames {
  static const today = 'execution-today';
  static const commitments = 'execution-commitments';
  static const review = 'execution-review';
  static const actionDetail = 'execution-action-detail';
  static const commitmentDetail = 'execution-commitment-detail';
  static const projectDetail = 'execution-project-detail';
}
