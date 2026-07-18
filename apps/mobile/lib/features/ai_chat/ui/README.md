# AI Chat UI

Route-level surfaces and small shared chat widgets live in this directory.
Keep larger screen internals grouped by responsibility:

- `sheet/` for the overlay sheet shell.
- `messages/` for message bubble rendering.
- `proposals/` for proposal cards and editors.
- `sessions/` for the session list panel.
- `tools/` for tool invocation cards, inline views, and JSON renderers.

## UX contract

- Timeline owns answers; system meta is quiet (icon-only actions, no noisy chrome).
- Structured next steps: `ask_user` / proposals, plus up to 3 follow-up chips on the trailing complete assistant turn.
- Blank state is a single suggestion list (≤3); no stacked discovery chrome.
- Composer owns model profile caption and edit-and-resend drafts (visible edit banner).
- Answer-first turn layout: prose → primary visualization (pinned) → collapsed read-tool steps → propose/decision → follow-ups.
- Message actions only on the trailing assistant turn.
- Tool visualizations use `ToolResultSurface` (SoftCard) with honest metric labels.
- History list shows title + last-message preview + relative time; mobile history is a near-full-height sheet.
- Proposals: light (oneTap) vs heavy (confirmDiff/typed); applied state is a meta line.

Do not add page part files back to the `ui/` root.
