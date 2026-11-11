# Rust client · daily FinanceOS

Mode: Operate. Platform: Android native phone. Code-led implementation.
Scope: `apps/client`; root Flutter design documents remain separate.

## Direction contract

This records the choices confirmed during implementation. The initial direction
was kept in the draft app DESIGN.md; this separate surface contract was persisted
at review time, after that draft became the extracted design-system document.
It is not evidence of a previously approved visual comp or ranked concept board.

**THESIS:** Open on dated activity and make recording the next transaction immediate.
The user's confirmed entry preference is “先看流水，快速记一笔”.

**OWN-WORLD:** Porcelain background, graphite text, flat white groups, restrained iris
actions, exact tabular amounts, and one consistent thin line icon family. Use
native system typography and matching ink/slate dark roles.

**STORY:** See this month's activity, capture income/expense/transfer, inspect and
correct it, reconcile account balances, and preserve/recover the local ledger.

**FIRST VIEWPORT:** Title and “记一笔” at the top; compact month selector, paired
currency-separated monthly totals, visible search and one filter trigger, then
dated rows. Persistent labelled navigation stays above system navigation.

**FORM:** Chronological ledger with a guarded full-page record editor and focused
account/choice sheets. User selected the recommended ledger-first entry. A ranked
visual-form board was not retained. Seed reference: `seed:bc868e4e5077d7f6`;
corroboration: `../questions/seeds/bc868e4e5077d7f6.json`.

**FINISH:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## QUALITY BAR

Review criteria derived from the confirmed task and native craft floor; this is
not represented as a recovered concept-seed output card.

- Ledger and quick capture are findable immediately; repeated daily work remains
  usable without restarting the app.
- Income, expense, transfer and currency are readable without color alone; exact
  amounts stay visible at narrow width and enlarged text.
- Inputs and hints remain readable in both appearances; guarded commits, errors,
  loading, empty states, keyboard and system insets support the complete task.
- Daily bookkeeping and encrypted recovery have real native evidence. iOS, ARM
  physical devices, live cloud sync, and investment features are outside that proof.
