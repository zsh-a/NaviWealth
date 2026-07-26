import '../domain/execution_models.dart';

String? executionProjectTitle(List<ExecutionProject> projects, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final project in projects) {
    if (project.id == id) return project.title;
  }
  return null;
}

String? executionCommitmentTitle(
  List<ExecutionCommitment> commitments,
  String? id,
) {
  if (id == null || id.isEmpty) return null;
  for (final commitment in commitments) {
    if (commitment.id == id) return commitment.title;
  }
  return null;
}

Map<String, Object?> executionActionJson(
  ExecutionAction action, {
  List<ExecutionProject> projects = const <ExecutionProject>[],
  List<ExecutionCommitment> commitments = const <ExecutionCommitment>[],
}) => <String, Object?>{
  'id': action.id,
  'title': action.title,
  'note': action.note,
  'status': action.status.wire,
  'priority': action.priority.wire,
  'due_at': action.dueAt?.toUtc().toIso8601String(),
  'scheduled_for': action.scheduledFor?.toUtc().toIso8601String(),
  'project_id': action.projectId,
  'project_title': executionProjectTitle(projects, action.projectId),
  'commitment_id': action.commitmentId,
  'commitment_title': executionCommitmentTitle(
    commitments,
    action.commitmentId,
  ),
  'source_domain': action.source.domain,
  'source_row_family': action.source.rowFamily,
  'source_row_id': action.source.rowId,
  'source_label': action.source.labelSnapshot,
  'created_at': action.createdAt.toUtc().toIso8601String(),
  'updated_at': action.sync.updatedAt.toUtc().toIso8601String(),
  'completed_at': action.completedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> executionProjectJson(ExecutionProject project) =>
    <String, Object?>{
      'id': project.id,
      'title': project.title,
      'description': project.description,
      'status': project.status.wire,
      'horizon': project.horizon.wire,
      'target_date': project.targetDate?.toUtc().toIso8601String(),
    };

Map<String, Object?> executionCommitmentJson(
  ExecutionCommitment commitment, {
  required List<ExecutionProject> projects,
}) => <String, Object?>{
  'id': commitment.id,
  'title': commitment.title,
  'description': commitment.description,
  'status': commitment.status.wire,
  'horizon': commitment.horizon.wire,
  'target_date': commitment.targetDate?.toUtc().toIso8601String(),
  'project_id': commitment.projectId,
  'project_title': executionProjectTitle(projects, commitment.projectId),
};
