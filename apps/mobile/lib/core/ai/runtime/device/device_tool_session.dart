/// Per-invocation domain-neutral context for device tools.
///
/// Conversation and provider state belong to the Agent Runtime. Domain tools
/// resolve their source data through their scoped DeviceToolContext.
library;

class DeviceToolSession {
  const DeviceToolSession();
}
