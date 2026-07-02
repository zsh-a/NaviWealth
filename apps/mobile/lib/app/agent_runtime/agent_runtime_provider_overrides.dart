/// Production provider overrides that route app AI surfaces through FRB-backed
/// agent-runtime integrations.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import 'agent_runtime_app_overrides.dart';
import 'agent_runtime_execution_overrides.dart';
import 'agent_runtime_health_overrides.dart';
import 'agent_runtime_knowledge_overrides.dart';

List<Override> agentRuntimeProviderOverrides() => <Override>[
  ...agentRuntimeAppProviderOverrides(),
  ...agentRuntimeHealthProviderOverrides(),
  ...agentRuntimeKnowledgeProviderOverrides(),
  ...agentRuntimeExecutionProviderOverrides(),
];
