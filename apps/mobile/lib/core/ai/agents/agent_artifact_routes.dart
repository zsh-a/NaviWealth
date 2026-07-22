/// Canonical route contract for persisted Agent results.
library;

abstract final class AgentArtifactRoutes {
  static const detailPath = '/insights/:artifactId';
  static const detailName = 'agent-artifact-detail';

  static String detail(String artifactId) =>
      '/insights/${Uri.encodeComponent(artifactId)}';
}
