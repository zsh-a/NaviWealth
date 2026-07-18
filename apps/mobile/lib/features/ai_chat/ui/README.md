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
- Structured next steps: pending proposal / interactive decision own focus; follow-up chips only when neither is blocking.
- Blank state is a single suggestion list (≤3) on full page and sheet; no stacked discovery chrome.
- Composer owns model profile caption and edit-and-resend drafts (visible edit banner).
- Answer-first turn layout: prose → primary visualization (pinned) → collapsed read-tool steps → propose/decision → follow-ups.
- Message actions: icon bar on trailing assistant; long-press action sheet on any message.
- Tool visualizations use `ToolResultSurface` (SoftCard) with honest metric labels and domain jump links.
- History list shows title + last-message preview + relative time; mobile history is a near-full-height sheet.
- Timeline date separators + jump-to-latest chip with unseen count.
- Proposals: primary Confirm CTA, SoftCard surfaces, success haptic; applied state is a quiet soft meta row with timed undo.

Do not add page part files back to the `ui/` root.
