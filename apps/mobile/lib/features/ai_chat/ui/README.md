# AI Chat UI

Route-level surfaces and small shared chat widgets live in this directory.
Keep larger screen internals grouped by responsibility:

- `sheet/` for the overlay sheet shell.
- `messages/` for message bubble rendering.
- `proposals/` for proposal cards and editors.
- `sessions/` for the session list panel.
- `tools/` for tool invocation cards, inline views, and JSON renderers.

## UX contract

- Timeline owns answers; system meta is quiet (icon-only actions, no canned reply chips).
- Next-step UI is structured only (`ask_user` / proposals), same on page and sheet.
- Blank state is a single suggestion list (≤3); no stacked discovery chrome.
- Composer owns model profile caption and edit-and-resend drafts.
- Answer-first turn layout: prose → collapsed read-tool steps → propose/decision.
- Message actions only on the trailing assistant turn.
- Proposals: light (oneTap) vs heavy (confirmDiff/typed); applied state is a meta line.

Do not add page part files back to the `ui/` root.
