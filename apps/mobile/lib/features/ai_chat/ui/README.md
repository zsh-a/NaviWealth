# AI Chat UI

Route-level surfaces and small shared chat widgets live in this directory.
Keep larger screen internals grouped by responsibility:

- `sheet/` for the overlay sheet shell.
- `messages/` for message bubble rendering.
- `proposals/` for proposal cards and editors.
- `sessions/` for the session list panel.
- `tools/` for tool invocation cards, inline views, and JSON renderers.

Do not add page part files back to the `ui/` root.
