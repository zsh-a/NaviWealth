#!/usr/bin/env bash
# Guardrail: production business entrypoints should use the FRB LLM/profile
# bridge, not the legacy direct-Dart DeviceLlmClient/DeviceLlmRuntime seams.
#
# The direct seams still exist for focused runtime/provider tests, explicit
# legacy fallback adapters, and low-level provider implementations. Production
# app/domain integrations should route through AgentRuntimeLlmBridge /
# AgentRuntimeProfileTurnRunner / FrbChatRunner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

ALLOWLIST_REGEX='apps/mobile/lib/core/ai/runtime/|apps/mobile/lib/features/ingest/data/device_ingest_client\.dart|apps/mobile/lib/features/knowledge/data/llm_capture_classifier\.dart'

PATTERN='deviceLlmClientProvider|deviceLlmRuntimeProvider|DirectLlmConnectivityProbe|DeviceVisionIngestClient|LlmBriefingSynthesizer\(client:|DeviceLlmClient|DeviceLlmRuntime'

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
  echo "business/app integrations. Extend this allowlist only for explicit" >&2
  echo "legacy/runtime infrastructure with a documented reason." >&2
  exit 1
fi

echo "✓ production LLM entrypoints stay on FRB seams."
