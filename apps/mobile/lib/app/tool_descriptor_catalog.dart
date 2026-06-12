/// Full AI tool descriptor catalog for tests, diagnostics, and generated docs.
///
/// Runtime composition uses `toolDescriptorLookupProvider`, which is scoped to
/// active domain packs. This static catalog intentionally lives in `app/`
/// because it imports every production domain.
library;

import '../core/ai/contracts/tool_descriptor.dart';
import '../core/ai/runtime/device/tools/device_tool_registry.dart'
    show kShellToolDescriptors;
import 'domain_composition.dart';
import 'domain_packs.dart';

final List<ToolDescriptor> allToolDescriptors =
    List<ToolDescriptor>.unmodifiable(
      domainToolDescriptors(kAllDomainPacks).values,
    );

final Map<String, ToolDescriptor> _byName = <String, ToolDescriptor>{
  ...kShellToolDescriptors,
  ...domainToolDescriptors(kAllDomainPacks),
};

ToolDescriptor? lookupToolDescriptor(String name) => _byName[name];
