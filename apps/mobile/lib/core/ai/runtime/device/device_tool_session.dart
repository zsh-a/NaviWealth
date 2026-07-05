/// Per-turn local tool execution context.
///
/// This stays smaller than the legacy chat [DeviceSession]. FRB tool-host
/// calls need local tool context, but they should not construct
/// provider-specific message objects just to execute Drift-backed tools.
library;

class DeviceToolSession {
  const DeviceToolSession({this.portfolioSnapshot});

  /// Device-derived portfolio snapshot threaded to tools that need it.
  final Map<String, Object?>? portfolioSnapshot;
}
