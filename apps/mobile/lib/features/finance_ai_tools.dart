/// FinanceOS device-tool registry surface (`docs/lifeos-shell.md`
/// §7.1, D-1.2).
///
/// Phase D-1.2 step 1: this barrel collects every Finance-domain tool
/// that the device runtime advertises. The tool *implementations*
/// still live under `core/ai/runtime/device/tools/` as a known
/// exception (northstar §2.2) — moving the 30+ implementation files
/// is a follow-up batch tracked in `lifeos-shell.md` §7.1. The
/// composition root is in place so HealthOS D-2 can land its tools
/// in `features/health/ai_tools/` and bootstrap merges them without
/// any further shell change.
library;

import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart'
    show kDeviceTools;

/// All FinanceOS device tools — every tool in [kDeviceTools] whose
/// descriptor isn't a shell-level tool (Memory Layer's `build_context`
/// / `query_memory`). The filter is by `ToolDescriptor.domain` so
/// adding a new shell tool automatically excludes itself from this
/// list — no string-matching, no allow-list to maintain.
final List<DeviceTool> kFinanceDeviceTools = kDeviceTools
    .where((tool) => lookupToolDescriptor(tool.name)?.domain != kDomainShell)
    .toList(growable: false);

/// Tools that the shell ships independent of any domain. Phase D-1.2:
/// the two Memory Layer tools. HealthOS D-2 will not need to touch
/// this — it adds its tools to a separate `kHealthDeviceTools` list.
final List<DeviceTool> kShellDeviceTools = kDeviceTools
    .where((tool) => lookupToolDescriptor(tool.name)?.domain == kDomainShell)
    .toList(growable: false);
