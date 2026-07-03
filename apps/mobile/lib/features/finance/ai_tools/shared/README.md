# Finance AI Tool Shared Helpers

Helpers in this directory are shared only by FinanceOS device AI tools.

- `propose/`: Finance proposal parsing and reference-resolution helpers.
- `scoped/`: Scoped window parsing, limits, and purpose validation.

Cross-domain AI contracts belong in `core/ai/`; slice-specific tool logic stays
inside the owning Finance slice's `ai_tools/` directory.
