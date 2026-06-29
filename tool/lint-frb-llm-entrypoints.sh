#!/usr/bin/env bash
# Guardrail: production business entrypoints should use the FRB LLM/profile
# bridge, not direct-Dart provider clients or legacy runtime names.
#
# Direct provider clients still exist only for focused runtime/provider tests
# and low-level provider implementations. Production app/domain integrations
# should route through AgentRuntimeLlmBridge / AgentRuntimeProfileTurnRunner /
# FrbChatRunner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

ALLOWLIST_REGEX='apps/mobile/lib/core/ai/runtime/'

PATTERN='deviceLlmClientProvider|deviceLlmRuntimeProvider|DirectLlmConnectivityProbe|DeviceVisionIngestClient|LlmBriefingSynthesizer\(client:|DeviceLlmClient|DeviceLlmRuntime|runtime/device/(anthropic|openai)/.*_client\.dart'
FEATURE_FRB_BRIDGE_PATTERN="app/agent_runtime_llm_bridge.dart|agentRuntimeLlmBridgeProvider"

violations="$(
  grep -rnE --include='*.dart' "$PATTERN" "$LIB" \
    | grep -vE "$ALLOWLIST_REGEX" \
    || true
)"

if [[ -n "$violations" ]]; then
  echo "✖ direct Dart LLM seam used outside FRB/legacy allowlist:" >&2
  echo "$violations" >&2
  echo >&2
  echo "Use AgentRuntimeLlmBridge or AgentRuntimeProfileTurnRunner for new" >&2
  echo "business/app integrations. Extend this allowlist only for low-level" >&2
  echo "runtime/provider infrastructure with a documented reason." >&2
  exit 1
fi

feature_bridge_violations="$(
  grep -rnE --include='*.dart' "$FEATURE_FRB_BRIDGE_PATTERN" "$LIB/features" \
    || true
)"

if [[ -n "$feature_bridge_violations" ]]; then
  echo "✖ feature code imports app-level FRB LLM bridge directly:" >&2
  echo "$feature_bridge_violations" >&2
  echo >&2
  echo "Features should own a small domain seam and let app/bootstrap.dart" >&2
  echo "inject an FRB-backed adapter from AgentRuntimeLlmBridge." >&2
  exit 1
fi

echo "✓ production LLM entrypoints stay on FRB seams."
