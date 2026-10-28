/// HealthOS route path contract.
library;

abstract final class HealthRoutes {
  static const today = '/health';
  static const trend = '/health/trend';
  static const meals = '/health/meals';
  static const mealNew = '/health/meals/new';
  static String mealEdit(String id) => '$meals/${Uri.encodeComponent(id)}';
}

abstract final class HealthRouteNames {
  static const today = 'health-today';
  static const trend = 'health-trend';
  static const meals = 'health-meals';
  static const mealNew = 'health-meal-new';
  static const mealEdit = 'health-meal-edit';
}
