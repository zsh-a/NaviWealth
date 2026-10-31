# NaviWealth

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Flutter ships one Personal LifeOS to Android, iOS, and Web. Web uses CanvasKit;
Impeccable's HTML/CSS detector and live editor do not validate the Dart UI.

## Users

Individuals managing their own finances and, optionally, health, knowledge,
and execution. Further audience research is open; do not invent personas.

## Product Purpose

Help people inspect their current situation, capture records, and take the
next concrete action. Frequent use should remain dense, readable, and direct.

## Capabilities and Constraints

Product and architectural truth remains in [the agent map](docs/agent-map.md),
[the architecture](docs/architecture/lifeos-architecture-northstar.md), and
[the shell contract](docs/architecture/lifeos-shell.md). Domain registries and
code own the current inventory. This file routes design work to those sources;
it does not introduce a competing feature specification.

The user authorized a replacement visual identity using Impeccable. Preserve
working navigation, data, interactions, opt-ins, and domain boundaries. Use
Forui and the existing Flutter design system; theme values remain authored in
Dart. English and Chinese, financial privacy, market-direction preferences,
dark appearance, text scaling, high contrast, and reduced motion are required.

## Brand Commitments

Preserve the NaviWealth name and product terminology. No new logo, claims,
marketing screens, or external font service is required by this redesign.

## Evidence on Hand

Existing implementation, domain documentation, widget tests, and committed
goldens under `apps/mobile/test/golden/` supply product and visual evidence.
Golden fixtures are synthetic; screenshots do not establish device performance.

## Product Principles

- Keep the user's primary task and current state easy to identify.
- Use shared components so all domains receive the same quality of treatment.
- Express meaning through text and structure as well as color.
- Keep preferences and local-first behavior intact through visual changes.
