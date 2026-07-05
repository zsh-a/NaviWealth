/// Provider-neutral device tool schema.
///
/// The shape intentionally matches the agent-runtime catalog and common LLM
/// tool schema fields. Provider adapters may serialize it into their own wire
/// dialect, but the app/runtime registry should not expose provider-specific
/// schema classes.
library;

class DeviceToolSchema {
  const DeviceToolSchema({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'input_schema': inputSchema,
  };
}
