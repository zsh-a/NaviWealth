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
