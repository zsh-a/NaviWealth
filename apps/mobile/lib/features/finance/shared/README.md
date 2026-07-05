# Finance Shared

Finance-only shared code lives here when more than one Finance slice needs it.
Keep the root free of Dart files:

- `l10n/`: Finance display labels and localization helpers.
- `ui/`: Finance UI widgets shared across slices.
- `ui/forms/`: Finance-specific form controls layered on `core/forms/`.

Domain-neutral helpers belong in `core/`, and slice-specific code should stay
inside that slice.
