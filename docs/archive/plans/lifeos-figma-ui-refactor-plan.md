# LifeOS Figma UI Refactor Plan

Source file: https://www.figma.com/design/mFcNfsFmFNVYwdhSfO8f5z/Untitled

Inspected Figma nodes:

- `4:233` — FinanceOS / wealth dashboard direction.
- `4:468` — HealthOS morning briefing / recovery direction.
- `4:5` — KnowledgeOS memory and principles direction.
- `4:652` — cross-domain LifeOS dashboard direction. The Figma MCP rate limit
  was reached before full context could be fetched for this node; earlier
  metadata showed a multi-domain dashboard with finance, health, knowledge
  metrics and an activity feed. Re-fetch before final pixel work.

## Goal

Refactor NaviWealth's Flutter UI style across the active LifeOS domains:
FinanceOS, HealthOS, KnowledgeOS, and the cross-domain Home/LifeOS dashboard.

This is a visual refactor only. Preserve current business logic, local-first
data ownership, routes, repositories, sync behavior, AI tool flows, domain
registration, and platform boundaries.

The Figma designs should be treated as a unified visual language, not as
drop-in React/Tailwind output. The implementation must use the existing Flutter
stack: Forui, local design-system tokens, `SoftCard`, `AppSection`,
`AdaptiveContentFrame`, `ResponsiveTwoColumn`, existing chart primitives, and
domain-local widgets.

## Design Translation

Shared visual cues from the Figma file:

- Cool off-white canvas: `#f7f9fb`.
- Deep slate primary: `#091426` / `#1e293b`.
- Finance accent: emerald `#006c49`.
- Health accent: rose / pink, with success green for recovery.
- Knowledge accent: cyan / sky `#0099d9`.
- Soft glass-lite cards: translucent white, subtle top highlight, low-opacity
  slate shadow, rounded 12 to 24px corners.
- Large calm hero cards for each OS.
- Compact bento sections for secondary data.
- Icon-led headings, small metadata pills, progress rings/bars, and concise
  action affordances.

Flutter adaptation rules:

- Do not add Tailwind, web CSS, or Figma remote assets to runtime.
- Use `FLucideIcons` and existing chart/custom-painter components.
- Prefer tokenized `AppSpacing`, `AppRadius`, `AppOpacity`, `AppShadow`,
  `TypographyTokens`, `SoftCardLevel`, and semantic/domain accent colors.
- Keep app shell chrome owned by Flutter (`ShellTabScaffold`,
  `AppCanvasScaffold`, domain tabs, existing bottom nav). Do not duplicate
  Figma top bars or bottom docks inside pages.
- Use Figma sample content only to infer layout; never seed it as user data.

## Current Code Entry Points

Cross-domain Home / LifeOS dashboard:

- `apps/mobile/lib/features/home/home_page.dart`
- `apps/mobile/lib/features/home/ui/home_greeting_header.dart`
- `apps/mobile/lib/features/home/ui/ai_insight_feed.dart`
- `apps/mobile/lib/features/home/ui/activity_timeline_preview.dart`
- `apps/mobile/lib/features/home/ui/allocation_summary.dart`
- `apps/mobile/lib/features/home/ui/trend_card.dart`

FinanceOS / Wealth:

- `apps/mobile/lib/features/finance/ui/wealth/wealth_hub_page.dart`
- `apps/mobile/lib/features/finance/ui/wealth/wealth_perspective_section.dart`
- `apps/mobile/lib/features/finance/accounts/ui/account_grouped_sections.dart`
- `apps/mobile/lib/features/finance/cashflow/ui/passive_income_card.dart`
- `apps/mobile/lib/features/finance/cashflow/ui/cashflow_calendar_card.dart`

HealthOS:

- `apps/mobile/lib/features/health/ui/health_today_page.dart`
- `apps/mobile/lib/features/health/ui/garmin_sync_status_card.dart`
- `apps/mobile/lib/features/health/ui/recovery_verdict.dart`
- `apps/mobile/lib/features/health/ui/health_metric_colors.dart`

KnowledgeOS:

- `apps/mobile/lib/features/knowledge/ui/knowledge_inbox_page.dart`
- `apps/mobile/lib/features/knowledge/ui/knowledge_review_page.dart`
- `apps/mobile/lib/features/knowledge/ui/knowledge_library_page.dart`
- `apps/mobile/lib/features/knowledge/ui/_widgets.dart`
- `apps/mobile/lib/features/knowledge/ui/_ai_suggestions_card.dart`

Shared design system:

- `apps/mobile/lib/design_system/widgets/adaptive_content_frame.dart`
- `apps/mobile/lib/design_system/widgets/responsive_two_column.dart`
- `apps/mobile/lib/design_system/widgets/app_section.dart`
- `apps/mobile/lib/design_system/widgets/soft_card.dart`
- `apps/mobile/lib/design_system/widgets/domain_ai_prompt_bar.dart`
- `apps/mobile/lib/design_system/widgets/app_icon_tile.dart`
- `apps/mobile/lib/design_system/widgets/delta_chip.dart`
- `apps/mobile/lib/design_system/charts/`

## Phase 1 — Shared Visual Foundation

Create the cross-domain styling layer first so each OS gets the same visual
language without copy-paste.

- Extend shared card primitives only where the existing API already points:
  - `SoftCardLevel.flat`, `raised`, `hero`.
  - Border/top-highlight and ambient shadow behavior.
  - Optional dark hero variant for high-priority insight/progress cards.
- Add reusable page/section patterns if they do not already exist:
  - `DomainHeroHeader` or equivalent local helper for large metric heroes.
  - `DomainMetricTile` for compact metric cards.
  - `DomainSectionHeader` for icon + title + optional action.
  - `DomainMetaPill` for uppercase/status/category labels.
- Keep these primitives domain-neutral in `design_system/`.
- Keep domain-specific color choices in domain UI files or semantic accent
  helpers, not hardcoded throughout shared widgets.

Acceptance:

- No domain business imports from `design_system/`.
- Existing pages using `SoftCard` still compile.
- Existing dark/light theme behavior remains valid.

## Phase 2 — Cross-Domain Home / LifeOS Dashboard

Figma reference: `4:652`.

Intent:

- Align Home with the integrated LifeOS view: top-level finance, health, and
  knowledge signals, plus recent activity/AI insight.
- Preserve current Home business logic: `dashboardSnapshotProvider`,
  `dashboardInsightsProvider`, price/sync status, recurring materialization,
  amount privacy, and current dashboard widgets.

Implementation direction:

- Continue using `AppCanvasScaffold` and `AdaptiveContentFrame`.
- Keep the existing cockpit split for wide viewports.
- Restyle `_NetWorthHeader` as the finance hero pattern shared with Wealth.
- Treat existing `AiInsightFeed`, `ActivityTimelinePreview`,
  `AllocationSummary`, `TrendCard`, `PassiveIncomeCard`, and
  `CashflowCalendarCard` as content modules inside the new bento rhythm.
- Add Health and Knowledge summary cards only if the data already exists behind
  current providers/domain opt-ins. Otherwise reserve visual slots for enabled
  domains without faking data.

Non-goals:

- Do not add a second dashboard data model.
- Do not bypass domain opt-ins.
- Do not show Health or Knowledge data when those domains are disabled.

## Phase 3 — FinanceOS / Wealth Refactor

Figma reference: `4:233`.

Intent:

- Bring the Wealth hub closer to the Figma finance dashboard: net-worth hero,
  asset allocation list, cashflow summary, FIRE/progress card, liabilities, and
  insight card.
- Preserve current account, balance, dashboard snapshot, account navigation,
  and action panel flows.

Target changes:

- Replace `_WealthHubBody` manual padding/ListView with `AdaptiveContentFrame`.
- Restyle `_NetWorthHero`:
  - Large numeric display.
  - Asset/liability breakdown.
  - Delta/status chip using current `DeltaChip` / valuation status patterns.
  - Optional lightweight sparkline only if current dashboard trend data is
    available.
- Restyle `_WealthSectionGrid` into a Finance bento surface:
  - Accounts, Holdings, Watchlist, Liabilities keep their current routes.
  - Use icon-led compact action rows.
- Keep `AccountsGroupedSections` as the detailed account list, but align card
  radius, spacing, and row density with the new surface style.
- Map Figma FIRE/progress visuals to existing planning/FIRE components only
  where current code already has data. If no real provider exists on Wealth,
  link to the current planning surface rather than inventing values.
- Keep `showWealthActionPanel` and all route pushes unchanged.

## Phase 4 — HealthOS Refactor

Figma reference: `4:468`.

Intent:

- Convert Health Today into a polished morning briefing surface with recovery
  hero, AI recommendation, sleep/HRV focus cards, daily vitals, and sync status.
- Preserve current Health data providers, local platform sync, Garmin status,
  body measurement entry, trend navigation, and manual morning briefing logic.

Target changes:

- Keep `ShellTabScaffold` and the body-metric header action.
- Rework `HealthTodayPage` content into:
  - Date/greeting header when a localized greeting is available.
  - Recovery hero card using `recoverySignalProvider` and
    `recoverySparklineProvider`.
  - AI recommendation / briefing card backed by
    `latestMorningBriefingProvider`, not static Figma text.
  - Sleep and HRV focus cards backed by existing latest metric providers.
  - Daily vitals grid backed by `_MetricGrid`.
  - Sync/permissions notices kept visible but visually quieter.
- Existing `_MetricCard`, `_ValueBig`, `_TrendBadge`, `_SleepStageBar`, and
  custom painters should be reused or restyled, not replaced with fake SVGs.
- Use `HealthMetricColors` for domain accents.

Non-goals:

- Do not change HealthKit/Garmin sync semantics.
- Do not add cloud health processing.
- Do not fabricate missing recovery/sleep/HRV data.

## Phase 5 — KnowledgeOS Refactor

Figma reference: `4:5`.

Intent:

- Bring Knowledge Inbox, Review, and Library into the same glass-lite domain
  language: memory/principle hero, search/AI prompt, stacked principle/log
  surfaces, and compact review/library lists.
- Preserve current capture, search, review, triage, proposal, and local sync
  behavior.

Target changes:

- Add Knowledge-local visual helpers in `_widgets.dart` only for domain-specific
  details.
- Expose `SoftCardLevel` through `KnowledgeSection`.
- Inbox:
  - Add a large Knowledge header and integrated AI/search prompt.
  - Restyle note rows and metadata chips.
  - Keep create FAB and capture sheet unchanged.
- Review:
  - Make `KnowledgeAiSuggestionsCard` the hero/review intelligence panel.
  - Restyle due routines, due decisions, and stale assumptions.
  - Preserve selection, reorder, swipe, and bulk mutation behavior.
- Library:
  - Restyle `_LibraryTabBar` as compact icon-first pills.
  - Restyle search and object-family tiles.
  - Preserve weighted search, search history, filters, delete, and navigation.

## Phase 6 — Responsive And Shell Consistency

- Use `AdaptiveContentFrame` for page padding, max width, and right-rail layout.
- Use `ResponsiveTwoColumn` for bento surfaces that naturally split wide:
  - Home cockpit.
  - Wealth finance dashboard.
  - Health hero/insight plus metrics.
  - Knowledge review/library.
- Keep mobile side padding at `AppSpacing.s16`.
- Keep desktop content within `AdaptiveMaxWidth.page` or
  `AdaptiveMaxWidth.dashboard`.
- Do not nest cards inside cards. Use cards for repeated items, modals, and
  framed tools; use unframed layout for page sections.
- Ensure all long localized strings wrap or truncate cleanly in English and
  Chinese.

## Localization

- Reuse existing l10n strings first.
- Add English and Chinese ARB keys only for truly new visible labels.
- Avoid hardcoding Figma sample phrases like "Alex", "Friday, Oct 27",
  "$1,245,890.00", or "High Yield Opportunity".
- Domain copy should come from current state, providers, or localized strings.

## Testing And Verification

Format:

- `cd apps/mobile && rtk dart format lib/design_system lib/features/home lib/features/finance/ui/wealth lib/features/health lib/features/knowledge`

Static analysis:

- `cd apps/mobile && rtk flutter analyze --fatal-infos`

Focused tests:

- `cd apps/mobile && rtk flutter test test/features/knowledge`
- `cd apps/mobile && rtk flutter test test/features/health`
- `cd apps/mobile && rtk flutter test test/features/finance`
- Add or update widget tests for changed page-level behavior where current
  coverage exists.

Behavior checks:

- Wealth: account routes, action panel, grouped account list, privacy/status
  values where applicable.
- Health: sync notice, body measurement action, recovery loading/error/data,
  trend navigation, briefing run/update.
- Knowledge: create FAB, Inbox list, Review bulk actions, reorder/swipe,
  Library segment/search/delete/detail navigation.
- Home: dashboard snapshot loading/error/data, amount privacy, sync status,
  domain opt-in visibility.

Visual checks:

- Mobile width for all four surfaces.
- Wide viewport for `AdaptiveContentFrame` and `ResponsiveTwoColumn` behavior.
- Dark mode if the current app supports it for these surfaces.
- Chinese localization for dense pills, metric cards, and action labels.

## Risks And Mitigations

- Risk: Figma screens represent separate conceptual dashboards, while the app
  has existing domain IA.
  Mitigation: translate visual hierarchy and component language; keep current
  navigation and domain boundaries.

- Risk: shared primitive changes affect unrelated Finance/Health/Knowledge
  surfaces.
  Mitigation: add options to existing primitives; keep defaults compatible.

- Risk: glass/blur effects can hurt mobile performance.
  Mitigation: prefer tonal `SoftCard` layers and low-opacity shadows; avoid
  expensive blur except where already proven.

- Risk: Health/Knowledge cards may lack data in disabled domains.
  Mitigation: respect opt-ins and existing empty/loading states.

- Risk: Figma `4:652` was not fully fetched due rate limit.
  Mitigation: re-fetch the node before final Home implementation and compare
  screenshots before shipping.

## Suggested Implementation Order

1. Shared design-system refinements.
2. Home/LifeOS dashboard shell pass.
3. FinanceOS/Wealth pass.
4. HealthOS pass.
5. KnowledgeOS pass.
6. Cross-domain responsive polish and targeted tests.

Keep commits small enough to review:

- Commit 1: shared visual primitives.
- Commit 2: Home + Wealth.
- Commit 3: Health.
- Commit 4: Knowledge.
- Commit 5: tests and final visual polish.
