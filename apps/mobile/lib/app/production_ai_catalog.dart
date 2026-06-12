/// Full production AI catalogs for tests, diagnostics, and generated docs.
///
/// Runtime composition is still scoped through active domain packs. These
/// catalogs intentionally live in `app/` because they import every production
/// domain pack.
library;

import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/intent/intent.dart';
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart';
import 'domain_composition.dart';
import 'domain_packs.dart';

final List<DeviceTool> productionDeviceTools = List<DeviceTool>.unmodifiable(
  domainDeviceTools(kAllDomainPacks),
);

final DeviceToolRegistry productionDeviceToolRegistry = DeviceToolRegistry(
  productionDeviceTools,
);

final Map<String, ToolDescriptor> productionToolDescriptors =
    Map<String, ToolDescriptor>.unmodifiable(
      domainToolDescriptors(kAllDomainPacks),
    );

final IntentCatalog productionIntentCatalog = domainIntentCatalog(
  kAllDomainPacks,
);
