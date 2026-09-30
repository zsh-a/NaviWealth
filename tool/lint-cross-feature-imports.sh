#!/usr/bin/env bash
# Boundary lint: every `features/<A>/` stays free of imports and exports
# from `features/<B>/`, including relative and conditional URIs.
# See the layering rules in docs/architecture/lifeos-architecture-northstar.md.
# Finance slices are domain-local under features/finance; no legacy exemption
# remains. New feature directories are checked automatically.
#
# The former `features/shared/` bucket has been split into `core/forms/` and
# `features/finance/shared/`; keep the retired top-level bucket empty so
# cross-feature "shared" code does not grow back. Finance shared code must also
# stay categorized under `features/finance/shared/l10n/` or
# `features/finance/shared/ui/`, not as loose root files. `features/plan/` and
# `features/wealth/` were also folded back into FinanceOS UI; keep those
# top-level pseudo-features empty too.
# `features/` itself is only an index of real feature/domain directories; Dart
# files belong inside their owning feature directory.
# Features use `ui/` for UI code; keep legacy `presentation/` directories from
# growing back.
# Settings AI surfaces live under `features/settings/ui/ai/`; keep the settings
# UI root for the settings overview and non-AI top-level settings pages.
# Page-internal part files should stay grouped under local screen directories
# instead of repeating the page name in flat `ui/` folders.
# Avoid `_shared` source directories; use a regular `shared/` directory with a
# README when a domain-local shared layer is warranted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LINT_ROOT="$ROOT"

violations="$(python3 -B <<'PY'
import os
from pathlib import Path
import sys

root = Path(os.environ["LINT_ROOT"]).resolve()
sys.path.insert(0, str(root / "tool"))
from dart_dependencies import feature_for_path, iter_dart_dependencies

lib_root = root / "apps/mobile/lib"
features_root = root / "apps/mobile/lib/features"

hits = []
retired_features = {
    "shared": (
        "features/shared is retired; move domain-neutral code to core/ "
        "or Finance-specific code to features/finance/shared/"
    ),
    "plan": (
        "features/plan is retired; move Plan tab code to features/finance/ui/"
    ),
    "wealth": (
        "features/wealth is retired; move Wealth tab code to "
        "features/finance/ui/wealth/"
    ),
}
for retired, message in retired_features.items():
    retired_root = features_root / retired
    for path in sorted(retired_root.rglob("*.dart")) if retired_root.exists() else []:
        rel = path.relative_to(root)
        hits.append(f"{rel}: {message}")

for path in sorted(features_root.glob("*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Dart files must live under features/<feature>/; "
        "put domain barrels inside their owning domain directory"
    )

for path in sorted(features_root.rglob("_shared/*.dart")):
    rel = path.relative_to(root)
    hits.append(f"{rel}: Use shared/ instead of _shared/ for feature source")

finance_shared_root = features_root / "finance" / "shared"
for path in sorted(finance_shared_root.glob("*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Finance shared Dart files must live under "
        "features/finance/shared/l10n/ or features/finance/shared/ui/"
    )

settings_ui_root = features_root / "settings" / "ui"
for path in sorted(settings_ui_root.glob("ai_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Settings AI UI files must live under "
        "features/settings/ui/ai/"
    )

settings_ui_groups = {
    "settings_overview.dart": "features/settings/ui/overview/",
    "settings_overview_*.dart": "features/settings/ui/overview/",
    "sync_status_page.dart": "features/settings/ui/sync/",
    "sync_status_page_*.dart": "features/settings/ui/sync/",
}
for pattern, target in settings_ui_groups.items():
    for path in sorted(settings_ui_root.glob(pattern)):
        rel = path.relative_to(root)
        hits.append(f"{rel}: Settings UI support files must live under {target}")

settings_ai_root = settings_ui_root / "ai"
settings_ai_part_groups = {
    "ai_models_page_*.dart": "features/settings/ui/ai/models/",
    "ai_llm_credentials_page_*.dart": "features/settings/ui/ai/llm_credentials/",
    "ai_transparency_page_*.dart": "features/settings/ui/ai/transparency/",
    "ai_trace_waterfall.dart": "features/settings/ui/ai/transparency/",
}
for pattern, target in settings_ai_part_groups.items():
    for path in sorted(settings_ai_root.glob(pattern)):
        rel = path.relative_to(root)
        hits.append(f"{rel}: Settings AI page internals must live under {target}")

settings_sync_root = settings_ui_root / "sync"
for path in sorted(settings_sync_root.glob("sync_status_page_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Sync status page internals must live under "
        "features/settings/ui/sync/status/"
    )

options_income_ui_root = features_root / "finance" / "options_income" / "ui"
for path in sorted(options_income_ui_root.glob("income_planner_page*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Income Planner page files must live under "
        "features/finance/options_income/ui/income_planner/"
    )

income_planner_root = options_income_ui_root / "income_planner"
for path in sorted(income_planner_root.glob("income_planner_page_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Income Planner part files should use local names like "
        "body.dart, states.dart, or shared.dart"
    )

ai_chat_ui_root = features_root / "ai_chat" / "ui"
ai_chat_ui_part_groups = {
    "ai_sheet*.dart": "features/ai_chat/ui/sheet/",
    "message_bubble*.dart": "features/ai_chat/ui/messages/",
    "propose_card*.dart": "features/ai_chat/ui/proposals/",
    "propose_batch_actions.dart": "features/ai_chat/ui/proposals/",
    "proposal_*.dart": "features/ai_chat/ui/proposals/",
    "sessions_panel*.dart": "features/ai_chat/ui/sessions/",
    "tool_invocation*.dart": "features/ai_chat/ui/tools/",
}
for pattern, target in ai_chat_ui_part_groups.items():
    for path in sorted(ai_chat_ui_root.glob(pattern)):
        rel = path.relative_to(root)
        hits.append(f"{rel}: AI Chat UI internals must live under {target}")

legacy_ai_chat_renderer_root = ai_chat_ui_root / "tool_renderers"
for path in sorted(legacy_ai_chat_renderer_root.rglob("*.dart")) if legacy_ai_chat_renderer_root.exists() else []:
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: AI Chat tool renderers must live under "
        "features/ai_chat/ui/tools/renderers/"
    )

ai_chat_renderer_root = ai_chat_ui_root / "tools" / "renderers"
for path in sorted(ai_chat_renderer_root.glob("tool_invocation_renderers_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: AI Chat renderer part files should use local names like "
        "asset_allocation.dart or holdings.dart"
    )

cashflow_ui_root = features_root / "finance" / "cashflow" / "ui"
for path in sorted(cashflow_ui_root.glob("cashflow_page_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Cashflow page internals must live under "
        "features/finance/cashflow/ui/cashflow/"
    )

analytics_ui_root = features_root / "finance" / "analytics" / "ui"
for pattern in (
    "analytics_cash_flow_trend.dart",
    "analytics_fire_progress.dart",
    "analytics_overview_grid.dart",
    "analytics_shared_widgets.dart",
):
    for path in sorted(analytics_ui_root.glob(pattern)):
        rel = path.relative_to(root)
        hits.append(
            f"{rel}: Analytics page internals must live under "
            "features/finance/analytics/ui/analytics/"
        )

accounts_ui_root = features_root / "finance" / "accounts" / "ui"
for path in sorted(accounts_ui_root.glob("account_form_page_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Account Form page internals must live under "
        "features/finance/accounts/ui/account_form/"
    )

ingest_ui_root = features_root / "finance" / "ingest" / "ui"
for path in sorted(ingest_ui_root.glob("ingest_review_page_*.dart")):
    rel = path.relative_to(root)
    hits.append(
        f"{rel}: Ingest Review page internals must live under "
        "features/finance/ingest/ui/ingest_review/"
    )

for path in sorted(features_root.rglob("presentation/*.dart")):
    rel = path.relative_to(root)
    hits.append(f"{rel}: Feature UI files belong under a ui/ directory")

for path in sorted(features_root.rglob("*.dart")):
    src_feature = feature_for_path(path, features_root)
    for edge in iter_dart_dependencies(path, lib_root):
        target_feature = feature_for_path(edge.target, features_root)
        if target_feature is None or target_feature == src_feature:
            continue
        hits.append(
            f"{path.relative_to(root)}:{edge.line}: {src_feature} "
            f"{edge.directive}s features/{target_feature}: {edge.uri}"
        )

print("\n".join(hits))
PY
)"

if [[ -n "$violations" ]]; then
  echo "✖ feature boundary or structure violation detected (D-1.6):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ all feature boundaries and structure stay clean."
