import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/tool_descriptor.dart';
import '../runtime/device/tools/device_tool_registry.dart'
    show kShellToolDescriptors;

typedef ToolDescriptorLookup = ToolDescriptor? Function(String name);

/// Runtime-facing tool metadata lookup.
///
/// The default contains only shell-owned descriptors. The app composition root
/// overrides this with active domain descriptors from `DomainPack`s so core
/// runtime code can enforce policy without importing domain feature code.
final toolDescriptorLookupProvider = Provider<ToolDescriptorLookup>((ref) {
  return (name) => kShellToolDescriptors[name];
});
