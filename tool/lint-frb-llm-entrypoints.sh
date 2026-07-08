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
FEATURE_FRB_BRIDGE_PATTERN="app/agent_runtime/bridges/agent_runtime_llm_bridge.dart|agentRuntimeLlmBridgeProvider"
APP_FEATURE_DEVICE_LOOP_PATTERN="runtime/device/device_agent_loop.dart|DeviceAgentLoop"
RAW_DEVICE_UNAVAILABLE_TRACE_PATTERN="routingReason:[[:space:]]*['\"]device_unavailable['\"]"
RAW_LEGACY_VISION_TRACE_PATTERN="routingReason:[[:space:]]*['\"]device_vision_direct['\"]"
LEGACY_VISION_TRACE_CONSTANT_PATTERN='kDeviceVisionDirectRoutingReason'
RAW_FRB_AGENT_RUNTIME_IMPORT_PATTERN='(package:naviwealth/|\.\.?/)*src/rust/api/agent_runtime\.dart'

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

raw_frb_agent_runtime_import_violations="$(
  grep -rnE --include='*.dart' "$RAW_FRB_AGENT_RUNTIME_IMPORT_PATTERN" "$LIB" \
    | grep -vE 'apps/mobile/lib/app/agent_runtime/bridges/agent_runtime_(native|llm_stream)_bridge\.dart' \
    || true
)"

if [[ -n "$raw_frb_agent_runtime_import_violations" ]]; then
  echo "✖ raw FRB agent-runtime API imported outside app-level bridges:" >&2
  echo "$raw_frb_agent_runtime_import_violations" >&2
  echo >&2
  echo "Route Flutter code through AgentRuntimeNativeBridge or" >&2
  echo "AgentRuntimeLlmStreamBridge so storage policy and JSON decoding stay" >&2
  echo "centralized. Do not couple product code to native runtime internals." >&2
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

app_feature_device_loop_violations="$(
  grep -rnE --include='*.dart' "$APP_FEATURE_DEVICE_LOOP_PATTERN" \
    "$LIB/app" "$LIB/features" \
    || true
)"

if [[ -n "$app_feature_device_loop_violations" ]]; then
  echo "✖ app/feature production code references the legacy Dart device loop:" >&2
  echo "$app_feature_device_loop_violations" >&2
  echo >&2
  echo "Interactive chat and business LLM paths should enter through" >&2
  echo "FrbChatRunner, AgentRuntimeLlmBridge, or AgentRuntimeProfileTurnRunner." >&2
  exit 1
fi

raw_device_unavailable_trace_violations="$(
  grep -rnE --include='*.dart' "$RAW_DEVICE_UNAVAILABLE_TRACE_PATTERN" "$LIB" \
    || true
)"

if [[ -n "$raw_device_unavailable_trace_violations" ]]; then
  echo "✖ raw device_unavailable trace routing reason used in production:" >&2
  echo "$raw_device_unavailable_trace_violations" >&2
  echo >&2
  echo "Use kDeviceUnavailableRoutingReason from core/ai/contracts/ai_trace.dart" >&2
  echo "so FRB/device trace labels stay centralized." >&2
  exit 1
fi

raw_legacy_vision_trace_violations="$(
  grep -rnE --include='*.dart' "$RAW_LEGACY_VISION_TRACE_PATTERN" "$LIB" \
    || true
)"

if [[ -n "$raw_legacy_vision_trace_violations" ]]; then
  echo "✖ legacy device_vision_direct trace routing reason used in production:" >&2
  echo "$raw_legacy_vision_trace_violations" >&2
  echo >&2
  echo "Use kFrbVisionIngestRoutingReason for new Vision ingest traces." >&2
  echo "kDeviceVisionDirectRoutingReason is legacy compatibility only." >&2
  exit 1
fi

legacy_vision_trace_constant_violations="$(
  grep -rnE --include='*.dart' "$LEGACY_VISION_TRACE_CONSTANT_PATTERN" "$LIB" \
    | grep -vE 'apps/mobile/lib/core/ai/contracts/ai_trace\.dart' \
    || true
)"

if [[ -n "$legacy_vision_trace_constant_violations" ]]; then
  echo "✖ legacy Vision trace routing constant used in production:" >&2
  echo "$legacy_vision_trace_constant_violations" >&2
  echo >&2
  echo "Use kFrbVisionIngestRoutingReason for new Vision ingest traces." >&2
  echo "kDeviceVisionDirectRoutingReason is legacy compatibility only." >&2
  exit 1
fi

BOOTSTRAP="$LIB/app/bootstrap.dart"
RUNTIME_WIRING="$LIB/app/agent_runtime"

if ! grep -q '\.\.\.agentRuntimeProviderOverrides()' "$BOOTSTRAP"; then
  echo "✖ bootstrap does not install centralized FRB runtime overrides:" >&2
  echo "  $BOOTSTRAP" >&2
  echo >&2
  echo "Keep app/bootstrap.dart delegating to agentRuntimeProviderOverrides()" >&2
  echo "so runtime wiring stays centralized." >&2
  exit 1
fi

SCHEDULED_AGENT_FRB_OVERRIDES='
executionReviewAgentProvider FrbExecutionReviewReader
morningBriefingAgentProvider FrbBriefingSynthesizer
recoveryAlertAgentProvider FrbRecoveryAlertSignalReader
weeklySummaryAgentProvider FrbWeeklySummaryReader
reviewAgentProvider FrbReviewDueReader
assumptionAgentProvider FrbAssumptionReviewReader
inboxTriageAgentProvider FrbInboxTriageSourceReader
contradictionAgentProvider FrbContradictionSourceReader
routineDueAgentProvider FrbRoutineDueReader
'

while read -r provider frb_type; do
  [[ -z "$provider" ]] && continue
  if ! grep -qr "${provider}\.overrideWith" "$RUNTIME_WIRING"; then
    echo "✖ production scheduled agent provider is not overridden in runtime wiring:" >&2
    echo "  $provider" >&2
    echo >&2
    echo "Scheduled production agents must be wired under app/agent_runtime/ so" >&2
    echo "DomainPack agent registration receives FRB-backed seams." >&2
    exit 1
  fi
  if ! grep -qr "$frb_type" "$RUNTIME_WIRING"; then
    echo "✖ production scheduled agent is missing its FRB seam in runtime wiring:" >&2
    echo "  $provider -> $frb_type" >&2
    echo >&2
    echo "Keep repository/programmatic implementations as feature fallbacks, but" >&2
    echo "production runtime overrides should inject the FRB reader/synthesizer." >&2
    exit 1
  fi
done <<< "$SCHEDULED_AGENT_FRB_OVERRIDES"

for surface in \
  execution_review \
  health_morning_briefing \
  health_recovery_alert \
  health_weekly_summary \
  knowledge_review \
  knowledge_assumption \
  knowledge_inbox_triage \
  knowledge_contradiction \
  knowledge_routine_due; do
  if ! grep -qr "surface: '$surface'" "$RUNTIME_WIRING"; then
    echo "✖ production FRB scheduled agent is missing local trace capture:" >&2
    echo "  surface: $surface" >&2
    echo >&2
    echo "FRB scheduled-agent runs should record local AiTrace spans through" >&2
    echo "agentRuntimeTraceRecorderProvider for transparency/debugging." >&2
    exit 1
  fi
done

echo "✓ production LLM and scheduled-agent entrypoints stay on FRB seams."
