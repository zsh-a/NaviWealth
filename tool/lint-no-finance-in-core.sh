#!/usr/bin/env bash
# Boundary lint: `core/ai/runtime/` is the shell-only AI runtime
# (`docs/lifeos-shell.md` §7.1, D-1.2). It must not import from
# `features/<domain>/`.
#
# Phase D-1.2 ships the DomainPack composition root + `deviceToolsProvider`
# so each domain registers its own tools. The old Finance tool cluster has
# moved out of `core/ai/runtime/device/tools/`; this script protects against
# regressions by linting new shell runtime imports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/apps/mobile/lib/core/ai/runtime"

# Grandfathered paths — see northstar §2.2.
# After D-1.2 (2026-05-26) the only remaining exception is the chat
# events import: `core/ai/runtime/{ai_runtime, device/
# device_agent_loop, device/llm_stream_event}.dart` import
# `features/ai_chat/domain/chat_events.dart` (the shell-level chat
# event taxonomy). `chat_events.dart` belongs in `core/ai/contracts/`
# and will move in a D-1.6b follow-up; until then the inverse imports
# are catalogued here so the lint stays green.
GRANDFATHERED='core/ai/runtime/ai_runtime\.dart|core/ai/runtime/device/device_agent_loop\.dart|core/ai/runtime/device/llm_stream_event\.dart'

# Search `core/ai/runtime/` for any feature-domain import. Strip the
# grandfathered subtree first so today's existing files don't fail
# the check. Only `import` statements count — doc-comment mentions are
# explicitly excluded so contextual references don't trigger the lint.
violations="$(grep -rnE --include='*.dart' "^import\s+['\"][^'\"]*features/[a-z_]+/" "$RUNTIME" \
  | grep -vE "$GRANDFATHERED" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ core/ai/runtime/ imports features/ (boundary violation, D-1.2):" >&2
  echo "$violations" >&2
  echo >&2
  echo "Tools must live under features/<domain>/ai_tools/ and be" >&2
  echo "registered through the domain's DomainPack/deviceTools list." >&2
  exit 1
fi

echo "✓ core/ai/runtime/ stays domain-neutral (D-1.2 boundary holds)."
