/// Cross-domain AI device tool registration
/// (`docs/lifeos-shell.md` §7.1, D-1.2).
///
/// Phase D-1.2: the device tool registry is built as a composition
/// root. Shell ships only the runtime + Memory Layer tools
/// (`build_context`, `query_memory`). Each LifeOS domain registers
/// its own tool list via a Riverpod provider; bootstrap merges them.
/// Finance tools live in `features/finance/ai_tools/`, Health tools in
/// `features/health/ai_tools/`, etc. — no Finance tool remains under
/// `core/ai/runtime/device/tools/`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/device/tools/device_tool.dart';

/// Aggregated device tool list. Default is empty so a shell-only build
/// (no domains active) still wires the dispatcher; bootstrap overrides
/// it with the union of each active domain's `<domain>DeviceToolsProvider`.
final deviceToolsProvider = Provider<List<DeviceTool>>(
  (ref) => const <DeviceTool>[],
);
