/// Derived AI tool descriptor catalog.
///
/// Each LifeOS domain co-locates its descriptors with its tool barrel
/// (`kShellToolDescriptors`, `kFinanceToolDescriptors`,
/// `kHealthToolDescriptors`, `kKnowledgeToolDescriptors`). This file
/// is the single union those barrels merge into — kept separate from
/// `tool_descriptor.dart` so the contracts type definitions stay
/// cycle-free (they don't import `features/`).
///
/// Adding a tool means appending to its domain's descriptor map; the
/// union below picks it up automatically. There is no separate
/// hand-maintained catalog list to keep in sync — that was the
/// pre-Phase-D shape, retired here.
library;

import '../../../features/finance_ai_tools.dart' show kFinanceToolDescriptors;
import '../../../features/health_ai_tools.dart' show kHealthToolDescriptors;
import '../../../features/knowledge_ai_tools.dart'
    show kKnowledgeToolDescriptors;
import '../runtime/device/tools/device_tool_registry.dart'
    show kShellToolDescriptors;
import 'tool_descriptor.dart';

/// All known tool descriptors across every LifeOS domain. Order is
/// shell → finance → health → knowledge (stable for golden tests).
final List<ToolDescriptor> allToolDescriptors = List<ToolDescriptor>.unmodifiable([
  ...kShellToolDescriptors.values,
  ...kFinanceToolDescriptors.values,
  ...kHealthToolDescriptors.values,
  ...kKnowledgeToolDescriptors.values,
]);

/// O(1) name → descriptor lookup. Built once on first read.
final Map<String, ToolDescriptor> _byName = <String, ToolDescriptor>{
  ...kShellToolDescriptors,
  ...kFinanceToolDescriptors,
  ...kHealthToolDescriptors,
  ...kKnowledgeToolDescriptors,
};

ToolDescriptor? lookupToolDescriptor(String name) => _byName[name];
