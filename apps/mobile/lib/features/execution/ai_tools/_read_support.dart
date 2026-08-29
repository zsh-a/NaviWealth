import '../domain/execution_models.dart';

String? executionPlanTitle(List<ExecutionPlan> plans, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final plan in plans) {
    if (plan.id == id) return plan.title;
  }
  return null;
}

Map<String, Object?> executionActionJson(
  ExecutionAction action, {
  List<ExecutionPlan> plans = const <ExecutionPlan>[],
}) => <String, Object?>{
  'id': action.id,
  'title': action.title,
  'note': action.note,
  'status': action.status.wire,
  'priority': action.priority.wire,
  'due_at': action.dueAt?.toUtc().toIso8601String(),
  'scheduled_for': action.scheduledFor?.toUtc().toIso8601String(),
  'plan_id': action.planId,
  'plan_title': executionPlanTitle(plans, action.planId),
  'source_domain': action.source.domain,
  'source_row_family': action.source.rowFamily,
  'source_row_id': action.source.rowId,
  'source_label': action.source.labelSnapshot,
  'created_at': action.createdAt.toUtc().toIso8601String(),
  'updated_at': action.sync.updatedAt.toUtc().toIso8601String(),
  'completed_at': action.completedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> executionPlanJson(ExecutionPlan plan) => <String, Object?>{
  'id': plan.id,
  'title': plan.title,
  'description': plan.description,
  'status': plan.status.wire,
  'horizon': plan.horizon.wire,
  'target_date': plan.targetDate?.toUtc().toIso8601String(),
};
