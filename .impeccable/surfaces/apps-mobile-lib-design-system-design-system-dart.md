---
version: 1
slug: "apps-mobile-lib-design-system-design-system-dart"
primary_target: "apps/mobile/lib/design_system/design_system.dart"
related_targets: ["apps/mobile/lib/features/finance/home/ui/home_page.dart","apps/mobile/lib/design_system/widgets/floating_glass_nav.dart","apps/mobile/lib/app/shell/app_dock_shell.dart"]
---

# NaviWealth global visual redesign

Mode: Operate. Scope: shared Flutter theme, components, domain navigation,
and representative Finance, Health, Knowledge, Execution and Settings screens.
The user chose Porcelain globally, incorporating Lumen's navigation material.
Build directly in Flutter; HTML sketches are direction references, not
pixel-locked image comps. Preserve the existing routes, behavior and data.

## Direction contract

THESIS: A precise, quiet Personal LifeOS; eliminate the heavy floating-card
appearance while keeping each task and state immediately legible.

OWN-WORLD: Porcelain canvas, opaque white groups, graphite text, iris-blue
actions, continuous 16dp content corners, measured tabular numerals. Dark
appearance uses ink and slate rather than bright inverted surfaces.

STORY: Read the current situation, capture a record, then inspect its detail;
all four domains share the same hierarchy and interaction grammar.

FIRST VIEWPORT: Existing shell and domain destinations stay fixed. Finance
Today opens with a compact heading, an open net-worth figure and privacy
control, then three capture actions and one grouped recent-activity list.
Wide layouts keep actions beside the amount. Other domains inherit the
palette, type, groups and states. Lumen contributes a light floating dock,
a quiet selected surface, and restrained selection motion; solid and high
contrast remain supported.

FORM: Porcelain, first-ranked grounded direction; user explicitly approved
the Lumen navigation contribution. seed:c749a4a4b03ad567 (reroll 1).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
