/// Cross-domain Life hub route contract (Phase B spatial layer).
library;

abstract final class LifeRoutes {
  static const home = '/life';

  static String agentArtifact(String id) =>
      '$home/insights/${Uri.encodeComponent(id)}';
}

abstract final class LifeRouteNames {
  static const home = 'life';
  static const agentArtifact = 'life-agent-artifact';
}
