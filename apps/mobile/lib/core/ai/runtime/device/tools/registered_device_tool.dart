import '../../../contracts/intent.dart' show RiskLevel;
import '../../../contracts/privacy_budget.dart' show BudgetTier;
import '../../../contracts/tool_descriptor.dart';
import 'device_tool.dart';

/// One domain-owned device-tool registration.
///
/// Keeps the implementation and policy metadata in a single list so domain
/// barrels do not maintain separate tool and descriptor inventories.
class RegisteredDeviceTool {
  const RegisteredDeviceTool({
    required this.tool,
    required this.access,
    required this.risk,
    required this.requiresConfirmation,
    required this.allowedContextTier,
    required this.domain,
    this.sideEffect = SideEffect.none,
    this.visibleInAssistant = true,
  });

  final DeviceTool tool;
  final Access access;
  final RiskLevel risk;
  final Confirmation requiresConfirmation;
  final BudgetTier allowedContextTier;
  final SideEffect sideEffect;
  final String domain;

  /// Whether this tool is advertised to the conversational Assistant.
  ///
  /// Internal agents may still use registrations hidden here. This keeps
  /// deterministic detector/triage plumbing out of the user's generic tool
  /// catalog without weakening the device allow-list.
  final bool visibleInAssistant;

  ToolDescriptor get descriptor => ToolDescriptor(
    name: tool.name,
    access: access,
    risk: risk,
    requiresConfirmation: requiresConfirmation,
    allowedContextTier: allowedContextTier,
    sideEffect: sideEffect,
    domain: domain,
  );
}

/// Domain-scoped builder for common read/propose registrations.
///
/// Domain barrels keep one small instance and then list tools as
/// `registrar.read(...)` / `registrar.propose(...)`, which avoids repeating
/// access, confirmation, side-effect, and domain fields for every tool.
class DeviceToolRegistrationBuilder {
  const DeviceToolRegistrationBuilder(this.domain);

  final String domain;

  RegisteredDeviceTool read(
    DeviceTool tool, {
    RiskLevel risk = RiskLevel.info,
    BudgetTier tier = BudgetTier.small,
    bool visibleInAssistant = true,
  }) => RegisteredDeviceTool(
    tool: tool,
    access: Access.read,
    risk: risk,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: tier,
    domain: domain,
    visibleInAssistant: visibleInAssistant,
  );

  RegisteredDeviceTool propose(
    DeviceTool tool, {
    RiskLevel risk = RiskLevel.propose,
    BudgetTier tier = BudgetTier.small,
    bool visibleInAssistant = true,
  }) => RegisteredDeviceTool(
    tool: tool,
    access: Access.propose,
    risk: risk,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: tier,
    sideEffect: SideEffect.deviceLocalWrite,
    domain: domain,
    visibleInAssistant: visibleInAssistant,
  );
}

List<DeviceTool> registeredDeviceTools(List<RegisteredDeviceTool> entries) =>
    List<DeviceTool>.unmodifiable(entries.map((e) => e.tool));

List<DeviceTool> registeredAssistantDeviceTools(
  List<RegisteredDeviceTool> entries,
) => List<DeviceTool>.unmodifiable(
  entries.where((entry) => entry.visibleInAssistant).map((entry) => entry.tool),
);

Map<String, ToolDescriptor> registeredToolDescriptors(
  List<RegisteredDeviceTool> entries,
) => Map<String, ToolDescriptor>.unmodifiable(<String, ToolDescriptor>{
  for (final e in entries) e.tool.name: e.descriptor,
});
