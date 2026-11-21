# NaviWealth Product Scope (NSH Client)

Status: active product SSOT for the NSH client.

Last reviewed: 2026-11-19.

## Document Contract

Owns what the NSH client is for, which features exist, and which are
deliberately absent. [Personal Local Scope](../architecture/personal-local-scope.md)
records the scope decisions; the [roadmap](../roadmap/roadmap-nsh.md) owns delivery order.
The retired Flutter client's feature inventory is not a parity target.

## Promise

> Record what I spend and eat with almost no effort, see what I own, and
> review each week how things are going.

The primary user is the owner, on one Android phone. There is no onboarding,
account system, product analytics, or demand study. Scope is judged by
whether the owner uses a feature every day or every week.

## Rules For Every Feature

1. It answers a question asked daily or weekly. Otherwise it is not built.
2. Four tabs at most, no nested secondary navigation. Settings is a page
   reached from a corner action, not a tab.
3. AI turns a short description and/or image into record drafts. The user
   confirms before anything is saved. Capture is a bounded conversation
   ([Capture Conversation](../architecture/capture-conversation.md)):
   clarifications and corrections are turns inside one capture draft's
   thread, and the model only ever answers owner-initiated turns. There are
   no free-form chats, named agents, or autonomous/background agents, and no
   memory across drafts.
4. Anything derivable is derived, not entered: net worth, positions, monthly
   balance, averages.
5. Adding a new kind of record requires removing one or a written reason.
6. Business data stays on the device. Encrypted backup files go only to a
   location the owner configures, including their own WebDAV folder; there is
   no NaviWealth account, server backup or record sync.

## Tabs

| Tab | Answers | Contents |
|---|---|---|
| Today | What happened today? | Today only (history lives in Records): a summary of spending and intake so far, body metrics, sleep and Body Battery, today's records, and drafts awaiting confirmation |
| Records | What did I record? | One date-ordered timeline of transactions and meals; drafts awaiting confirmation (imports, recognition results) pinned on top |
| Assets | What do I own? | Accounts and balances, holdings with quantity, cost and market value, net worth and its trend |
| Review | How did this week / month go? | Spending by category vs the previous period (optional budget planned), net worth and holdings change, average intake and macros, weight trend, Garmin sleep/resting HR/steps averages, one line of the owner's own notes |

## Interaction Model

Updated 2026-11-14: the owner chose text-or-image capture with fewer forms.

- A floating tab bar beside one capture button. Capture opens one composer:
  describe what happened or attach up to four images per draft, including
  evidence added in later turns. Recognition routes to money,
  meals or body weight; the owner need not choose a domain or entry method.
  Explicitly requested multiple records are reviewed together, with their
  count on the confirmation action. A purchase description alone does not
  also create a meal. Unsupported or ambiguous input asks for clarification.
- Capture is a bounded conversation
  ([Capture Conversation](../architecture/capture-conversation.md)): the
  description or photo is the thread's first message, results and
  clarifying questions are the model's `ask_user` tool calls, and a correction is the next
  message. Decisions show a reason and unselected options with descriptions.
  The owner can change selections, add text or images, then submit answers
  together; the matching tool result continues the draft. Questions that name
  an account or category offer tap-first options. The thread lives inside one capture draft and ends with it.
  Missing money fields stay missing and prevent confirmation; a named new
  account is shown as new and created only when confirmed. AI never selects a funding
  account merely because a payment app appears in a screenshot.
- Recognition never blocks navigation. Input and results are local drafts,
  shared between Today and Records. Leaving while recognition runs keeps it
  running under the app root; a run interrupted by restart can be retried.
  Confirmation writes the entire batch and removes its draft atomically.
- Manual meal, money and weight entry are secondary actions under "Enter
  manually"; favorites retain one-tap logging with Undo. Manual money uses
  one compact editor: amount, category/account, a calendar date and optional
  details. Selection views replace the editor body; header and actions stay
  fixed above the keyboard. Only successful saves update remembered choices.
- The model/server consent names the text, attached images and account names
  being sent. It is remembered only for that model account and API protocol
  when requested. Model settings explicitly select Anthropic Messages, OpenAI
  Chat Completions or OpenAI Responses; Responses uses local history and
  disables server-side response storage.
- Today shows today. Past days are reached in Records; logging for another
  day changes the date on the review page.
- Today keeps one layout from health-only to finance: the summary card shows
  intake now and spending beside it once the ledger exists.
- No hidden gestures: every action is a visible control, nothing depends on
  a long press. Settings keep each change as it is made; there is no Save.
- Assets leads with net worth, compact totals and a continuous list of cash
  accounts, open holdings and debts. Cost/quantity and normal check dates are
  details; manual-price dates, cost fallback and unchecked status remain visible.
  Manage contains creation and closed-holding history; Asset changes opens the
  dated trend and valuation basis. Closed positions reappear after buying again.
  A single icon-only plus beside the tab bar opens capture; its accessible
  name is New entry / 新记录. Account and holding creation stay in Manage.
- Review leads with one sentence of what changed against the period before;
  a month is a calendar whose days open in Records, which has the same
  calendar; a chosen day is shown alone, stepping to neighbouring days.

## Kept Features

### Ledger (double-entry)

The ledger is double-entry: every transaction is a balanced set of postings,
so balances, spending and net worth are all derived from one journal and
must agree. Statement import is the main way money is recorded; manual entry
and screenshots fill gaps.

- **Accounts** of five types: Assets (cash, debit cards, Alipay and WeChat
  balances), Liabilities (credit cards, Huabei), Expenses and Income (these
  are the categories), and Equity (opening balances, adjustments). Names are
  `type:name` for CNY (`资产:招行储蓄卡`, `支出:餐饮`); foreign accounts
  include currency (`资产/USD:Broker cash`). A default set of expense and
  income accounts ships; the owner's own asset and liability accounts are
  created as statements first mention them.
- **Transactions:** a date and time, payee, note, source (statement row,
  manual, screenshot) and two or more postings in native currency minor units
  whose sum is zero separately within each currency. Initial currencies are
  CNY, HKD and USD. Cross-currency transfers record both sent and received
  amounts with currency-specific equity bridge postings. A purchase is `支出:餐饮 +31.50 / 资产:支付宝余额 −31.50`; a
  credit-card purchase posts to `负债:…`; a repayment or top-up moves money
  between own accounts; a refund reverses its purchase.
- **Statement import (primary):** the system file picker opens an Alipay CSV,
  WeChat XLSX or CMB credit-card statement text (PDF is not decoded); the
  `navi-finance` parsers match the statement corpus fixtures exactly.
  Each row's payment method (`余额`, `花呗`, `招商银行储蓄卡(1234)`) maps to an
  asset or liability account, asked once and remembered; its category hint
  and payee map to an expense or income account through remembered rules.
  A review page shows new, possible-duplicate and skipped rows; nothing is
  posted before confirmation. The local review draft survives restart; refunds
  and ambiguous movements require explicit correction. A changed journal is
  reviewed again before committing the batch.
- **Duplicates across sources:** a statement row repeats an earlier one when
  it carries the same provider transaction id, or posts the same amount to
  the same own account within a day (an Alipay purchase paid by credit card
  also appears on the card's statement). Possible duplicates start
  unselected.
- **Balance checks:** the owner states an account's real balance on a date;
  a difference is shown and can be posted to `权益:调整` with confirmation.
  Opening balances are postings against `权益:期初`. A confirmed balance entry
  can be revoked from its receipt; its postings and associated observation are
  removed together and restored together by Undo.
- Manual entry is a bottom sheet: amount, expense or income account, the own
  account it came from or went to, or a transfer between two own accounts.
- Existing ordinary transactions expose Delete on the main editor, with a
  confirmation of the saved record and Undo after success. Deletion and Undo
  are atomic, reject changed identities, and update balances and records only
  after commit. Investment entries remain governed by their trade deletion
  flow so cash and holdings stay consistent.
- Short descriptions, receipts or payment screenshots become reviewable
  transaction drafts through the owner's own model account. This capture
  path was brought forward by the owner's 2026-11-14 AI-native direction;
  statement import remains the primary bulk ingestion path.
- Planned, not yet implemented: one optional monthly budget against total
  expenses. No per-category budgets.

### Holdings (detail required)

Initial delivery (2026-11-15, owner: keep it simple): holdings appear directly
on Assets. A compact editor accepts a name/code, quantity and unit cost for an
existing position; purchases/sales/dividends also choose a cash account. Date
and fees are optional details. Derived quantities, average cost, gains and
cash balances come from confirmed trades. Prices are dated in each security’s
CNY, HKD or USD trading currency;
unpriced positions are explicitly valued at cost. Trade records are
necessary to answer what is owned and how its cost changes; editable standalone
position totals would conflict with the journal. AI trade capture is deferred.

The catalog and quote increment is implemented: code/name/pinyin/alias search
uses the catalog downloaded from the rolling GitHub release, checked lazily.
Linking
an existing holding requires confirmation and preserves its identity and trades.
Initial supported markets are mainland China, Hong Kong and US stocks and
ETFs, in CNY, HKD and USD. A holding’s currency is immutable; buy, sell and
dividend cash accounts must match it. Costs and gains remain native amounts.
Tencent quotes update automatically for open linked holdings when the app is active.
Unlinked holdings can be priced by hand. Existing manual prices win on the same or newer day. Failed updates retain the previous dated mark.

The asset overview converts to CNY using the latest rate dated on or before
the valuation date. Missing rates exclude those currencies and visibly label
the result as known value; history never presents a partial series as complete.
HKD/CNY and USD/CNY reference rates update automatically. The rates view shows
the saved value, date and source. Existing manual rates win same-day ties. Schema 14 preserves dated rates in local backups. Other
currencies and crypto remain unsupported. Android TLS and physical-device
checks remain unverified.

The full target is:

- Securities from the existing catalog shipped via GitHub Releases.
- Trades: buy, sell, dividend, fee. Positions, average cost, realized and
  unrealized gain are derived from trades.
- Automatic foreground quotes from one market-data provider;
  FX conversion to the base currency.

### Health

- Meal logging as in the current NSH client: photo recognition with consent,
  editable consumed grams, local catalog nutrition, manual entry. The
  catalog nutrition covers energy and macros plus fibre, sugars, sodium and
  saturated fat; the model's estimate may add these and the owner edits them
  in the food editor. Foods without these values still save; sums show them
  as partial.
- Favorites: a saved meal kept as a favorite (its own copy, photo shared)
  logs again on any day with one tap and Undo; the logged meal is adjusted
  like any other. It
  replaced "log again today", which could only copy a meal still in the
  four-week strip onto today (Rule 5).
- Weight: manual entry plus Garmin body composition when available. A weight
  day may carry an estimated body composition — body fat, muscle and water
  shares with the estimating formula and impedance as provenance (Rule 5
  reason: composition answers the same daily question as weight, how the
  body changes beyond mass). BMI is shown, never stored: computed from the
  weight and the frozen measurement height when available (manual weights use
  the current height in Settings' body profile), which also keeps the birth
  date and sex the estimates need. Completed age is calculated on the local
  measurement day and frozen with the measurement; old entered ages remain
  a labelled fallback until the owner supplies a birth date. The goal weight (Settings) shows the day's
  distance to it in Today's Body metrics overview and as a line in Review's weight chart, which has
  30- and 90-day windows. Nothing is estimated from a manually entered
  weight: composition arrives only with a scale measurement. Today calls this
  summary Body metrics: a full-width dated weight with a separate weekly trend,
  body-fat and BMI facts. It joins composition on the kept weight's day;
  missing data is a dash. Muscle, water, goals and original measurement details
  are disclosed in its overview. Garmin summaries retain their own equal-width
  row, stacking at large text. The scale link
  uses a foreground AFU-WL/Welland Bluetooth LE flow. A small TSX entry mounts
  the existing Rust pages and the scale sheet; Kotlin owns Android permissions,
  scanning and GATT through an explicit Host Channel whitelist. Rust owns packet
  validation, profile/time commands, estimation and atomic confirmation. A
  completed draft stays local and can be reopened without reconnecting.
  Opening measurement otherwise attempts the remembered scale once in the
  foreground; closing/backgrounding stops it. Dynamic weight updates live but
  cannot be confirmed before stability. Details may derive BMI and estimated
  fat/fat-free/muscle/water masses from the same measurement; estimates keep
  their model provenance and do not claim numerical parity with vendor scores.
  The owner can choose Segal (the legacy default), experimental Wu 2015, or
  experimental Sun 2003 in Body profile for future sessions. The measurement
  sheet can also recalculate its unsaved draft from the same original grams,
  ADCs and captured profile, without reconnecting or changing that preference.
  A changed draft rotates its confirmation token atomically and resets any
  replacement confirmation. Models outside their supported input range return
  weight only, with an explicit explanation and model-switch recovery; they
  never fall back to another composition formula. Sun independently estimates
  total body water; muscle remains a proportional approximation. Experimental
  models use reference-converted impedance, not a verified device calibration.
  Saved readings keep their model/version and are never recalculated by a
  preference change. Review shows body-fat curves separately by algorithm.
  Same-day
  replacement requires a second confirmation; missing valid impedance offers
  weight only and is explicitly unfinished. A slow composition reading keeps
  listening and offers remeasurement rather than claiming completion. Empty
  impedance packets cannot erase valid composition within the same load cycle;
  moving weight starts fresh evidence. Manual edits, deletion, Undo and backup
  preserve the association
  between weight and its measuring evidence. Host builds, packet fixtures and
  headless flows are verified; real-device measurements and signed in-place
  upgrade acceptance remain open (see the roadmap). This does not change
  Personal Local Scope's no-Keystore decision.
- Garmin daily data through Garmin's official Personal API (self-serve key,
  read-only, own data only): sleep duration and score, HRV with its status,
  resting heart rate, Body Battery high, steps and average stress. Pulled at
  app start and resume, at most every 30 minutes; the first pull covers 30
  days. The key's region (garmin.com or garmin.cn) is found by trying both.
  The reverse-engineered Garmin Connect client (password + MFA) is not
  ported. Garmin weight is not imported yet (no scale data to verify).

### Data

- A local SQLite database in the app's private storage (Android sandbox and
  file-based encryption; no SQLCipher, see Personal Local Scope).
- Automatic local backups plus manual export/restore of a passphrase-encrypted
  backup file to a location the owner picks; meal photos optional in the export.
  Provider market quotes and daily bars are re-fetchable caches, not records:
  snapshots leave them out, and a restored install rebuilds them from each
  holding's first trade.
- Update checks read the app's own public GitHub releases — read-only, no
  credentials, nothing sent — at most daily on open and on demand from
  Settings. A newer `nsh-v*` release shows its notes and a link to its
  release page; downloading and installing stay the owner's steps.
  The current Health increment uses an owner-configured WebDAV folder for
  daily foreground backups (without photos) and manual backup/restore
  (with meal photos), excluding credentials. Local file export waits for a
  save or share dialog on Android in NSH.

## Removed

| Removed | Note |
|---|---|
| Options income, rebalance, FIRE, income strategy, life events, analytics dashboards | Planning tools without a weekly question |
| Runway forecasts, Monthly Close workflow, Financial Inbox detectors | The Records drafts list and Review tab replace them |
| Investment notifications, dividend forecasts, multi-provider market data | One quote provider is enough |
| Recovery score/verdict, health check-ins, trend explorer, HealthKit, Health Connect | Garmin and manual data cover the owner's needs |
| KnowledgeOS (notes, decisions, relations, BCR library) | Whole domain |
| ExecutionOS (plans, actions, progress) | Whole domain |
| AI chat, the seven named agents, Memory Runtime, proposals, voice | AI is recognition only; the capture thread is a bounded clarification surface inside recognition ([Capture Conversation](../architecture/capture-conversation.md)), not chat |
| Sync v3, accounts/login, backend dependency | Local backups only |
| Domain opt-in, `DomainPack` registry, command palette, Life signals | Fixed composition of four tabs |
| Web and iOS | Decided 2026-11-13 |
| Flutter client and the Sync v3 backend | Retired 2026-11-15; archive at the `flutter-final` tag |
| Allocation display by asset class and currency | Answers no daily or weekly question; net worth and holdings answer "what do I own" |
| Broker statement import for trades | Fewer than ten trades a year; holdings stay manual entry |
| One-time Flutter data import | Flutter retires directly after archiving its backup  |

Removed data is not lost: the owner exports the full Flutter backup before
uninstalling, and the retired source stays reachable at the `flutter-final`
tag.

## Records In Scope

Account (assets, liabilities, expenses, income, equity), Transaction with
its postings, Import mapping rule, Balance check, Budget (optional),
Security, Trade, Quote,
Meal (with food snapshots and local photos), Favorite meal, Weight, Estimated body composition (per weight day, from a scale),
Garmin daily summary,
Review note. Balances, spending, positions and net worth are derived and not
stored as truth.


Historical prices remain a secondary Assets task: daily closes and corrections
are inspectable beneath Manage or a holding detail. Asset changes distinguishes
recalculated history from immutable observations captured at the shown time.
Missing FX stays explicit; neither retroactive snapshots nor closing-net-worth
claims are inferred from an ordinary foreground capture. Historical retrieval
uses the existing public data providers and preserves native currencies.
