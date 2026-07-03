/// Production provider overrides that route app AI surfaces through FRB-backed
/// agent-runtime integrations.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:naviwealth/app/agent_runtime/overrides/agent_runtime_app_overrides.dart';

List<Override> agentRuntimeProviderOverrides() => <Override>[
  ...agentRuntimeAppProviderOverrides(),
];
