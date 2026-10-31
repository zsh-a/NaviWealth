# Impeccable integration

Project-local Codex skill: `skills/impeccable/SKILL.md`.

- Upstream: https://github.com/pbakaus/impeccable
- Skill version: 4.8.0
- Pinned revision: `df3a4abe7d0840d5f60324812c432e00b66a4e75`
- License: Apache-2.0; the upstream license is retained with the skill.
- Installation source: upstream `.agents/skills/impeccable`, copied unchanged
  except for this license addition. No runtime dependency or design hook.

The skill becomes discoverable on the next Codex turn. Use `$impeccable`
followed by `audit`, `layout`, `adapt`, `harden`, or `polish` and a concrete
Flutter target. Run its context launcher from the repository root.

NaviWealth is a Flutter application. Use the native/adaptive playbooks and
rendered Flutter evidence. The HTML/CSS detector, DOM overlay, and live source
editor do not validate `.dart` or CanvasKit widgets. A clean detector result
must never stand in for widget, contrast, responsive, or golden verification.

Read `PRODUCT.md`, `DESIGN.md` when present, and the existing design-system
contract at `apps/mobile/docs/design/15-ui-refactor-blueprint.md`. Dart remains
the source of truth for tokens; regenerate the W3C export after token edits.
Repository architecture, Forui, navigation, privacy, localization, and user
appearance preferences constrain every design task. Platform guides do not
authorize replacing those established contracts.

To update, review upstream changes and replace the skill from a reviewed,
explicit revision; update this record and retain its license. Keep temporary
direction boards, captures, and local engine state out of commits.
