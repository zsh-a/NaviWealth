# NaviWealth Product Scope (NSH Client)

Status: active product SSOT for the NSH client.

Last reviewed: 2026-11-15.

## Document Contract

Owns what the NSH client is for, which features exist, and which are
deliberately absent. [ADR 0002](../architecture/adr/0002-personal-local-scope.md)
records the architectural consequences and
[ADR 0003](../architecture/adr/0003-flutter-retirement.md) records the Flutter
retirement; the [roadmap](../roadmap/roadmap-lifeos.md) owns delivery order.
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
   confirms before anything is saved. A correction is another short description
   applied to the current draft, not a chat timeline. No named agents or
   autonomous/background agents.
4. Anything derivable is derived, not entered: net worth, positions, monthly
   balance, averages.
5. Adding a new kind of record requires removing one or a written reason.
6. Business data stays on the device. Encrypted backup files go only to a
   location the owner configures, including their own WebDAV folder; there is
   no NaviWealth account, server backup or record sync.

## Tabs

| Tab | Answers | Contents |
|---|---|---|
| Today | What happened today? | Today only (history lives in Records): a summary of spending and intake so far, sleep, latest weight and Body Battery, today's records, and drafts awaiting confirmation |
| Records | What did I record? | One date-ordered timeline of transactions and meals; drafts awaiting confirmation (imports, recognition results) pinned on top |
| Assets | What do I own? | Accounts and balances, holdings with quantity, cost and market value, net worth and its trend |
| Review | How did this week / month go? | Spending by category vs the previous period and the optional budget, net worth and holdings change, average intake and macros, weight trend, Garmin sleep/resting HR/steps averages, one line of the owner's own notes |

## Interaction Model

Updated 2026-11-14: the owner chose text-or-image capture with fewer forms.

- A floating tab bar beside one capture button. Capture opens one composer:
  describe what happened or attach an image. Recognition routes to money,
  meals or body weight; the owner need not choose a domain or entry method.
  Explicitly requested multiple records are reviewed together, with their
  count on the confirmation action. A purchase description alone does not
  also create a meal. Unsupported or ambiguous input asks for clarification.
- The result is a readable summary, with a short correction box. Missing
  money fields stay missing and prevent confirmation; a named new account
  is shown as new and created only when confirmed. AI never selects a funding
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
- The model/server consent names the text, attached image and account names
  being sent. It is remembered only for that model account when requested.
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
  `finance-core` parsers match the statement corpus fixtures exactly.
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
  Opening balances are postings against `权益:期初`.
- Manual entry is a bottom sheet: amount, expense or income account, the own
  account it came from or went to, or a transfer between two own accounts.
- Short descriptions, receipts or payment screenshots become reviewable
  transaction drafts through the owner's own model account. This capture
  path was brought forward by the owner's 2026-11-14 AI-native direction;
  statement import remains the primary bulk ingestion path.
- One optional monthly budget against total expenses. No per-category
  budgets.

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
uses the verified bundled catalog, with lazy GitHub Releases updates. Linking
an existing holding requires confirmation and preserves its identity and trades.
Initial supported markets are mainland China, Hong Kong and US stocks and
ETFs, in CNY, HKD and USD. A holding’s currency is immutable; buy, sell and
dividend cash accounts must match it. Costs and gains remain native amounts.
Tencent quotes refresh at foreground entry and on demand; manual prices win on
the same or newer day. Failed updates retain the previous dated mark.

The asset overview converts to CNY using the latest rate dated on or before
the valuation date. Missing rates exclude those currencies and visibly label
the result as known value; history never presents a partial series as complete.
HKD/CNY and USD/CNY rates can refresh or be entered manually; manual rates win
on the same day. Schema 14 preserves dated rates in local backups. Other
currencies and crypto remain unsupported. Android TLS and physical-device
checks remain unverified.

The full target is:

- Securities from the existing catalog shipped via GitHub Releases.
- Trades: buy, sell, dividend, fee. Positions, average cost, realized and
  unrealized gain are derived from trades.
- Quote refresh from one market-data provider, on demand and at app start;
  FX conversion to the base currency.

### Health

- Meal logging as in the current NSH client: photo recognition with consent,
  editable consumed grams, local catalog nutrition, manual entry.
- Favorites: a saved meal kept as a favorite (its own copy, photo shared)
  logs again on any day with one tap and Undo; the logged meal is adjusted
  like any other. It
  replaced "log again today", which could only copy a meal still in the
  four-week strip onto today (Rule 5).
- Weight: manual entry plus Garmin body composition when available.
- Garmin daily data through Garmin's official Personal API (self-serve key,
  read-only, own data only): sleep duration and score, HRV with its status,
  resting heart rate, Body Battery high, steps and average stress. Pulled at
  app start and resume, at most every 30 minutes; the first pull covers 30
  days. The key's region (garmin.com or garmin.cn) is found by trying both.
  The reverse-engineered Garmin Connect client (password + MFA) is not
  ported. Garmin weight is not imported yet (no scale data to verify).

### Data

- A local SQLite database in the app's private storage (Android sandbox and
  file-based encryption; no SQLCipher, see ADR 0002).
- Automatic local backups plus manual export/restore of a passphrase-encrypted
  backup file to a location the owner picks; meal photos optional in the export.
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
| AI chat, the seven named agents, Memory Runtime, proposals, voice | AI is recognition only |
| Sync v3, accounts/login, backend dependency | Local backups only |
| Domain opt-in, `DomainPack` registry, command palette, Life signals | Fixed composition of four tabs |
| Web and iOS | Decided 2026-11-13 |
| Flutter client and the Sync v3 backend | Retired 2026-11-15 (ADR 0003); archive at the `flutter-final` tag |
| Allocation display by asset class and currency | Answers no daily or weekly question; net worth and holdings answer "what do I own" |
| Broker statement import for trades | Fewer than ten trades a year; holdings stay manual entry |
| One-time Flutter data import | Flutter retires directly after archiving its backup (ADR 0003) |

Removed data is not lost: the owner exports the full Flutter backup before
uninstalling, and the retired source stays reachable at the `flutter-final`
tag.

## Records In Scope

Account (assets, liabilities, expenses, income, equity), Transaction with
its postings, Import mapping rule, Balance check, Budget (optional),
Security, Trade, Quote,
Meal (with food snapshots and local photos), Favorite meal, Weight, Garmin daily summary,
Review note. Balances, spending, positions and net worth are derived and not
stored as truth.


Historical prices remain a secondary Assets task: daily closes and corrections
are inspectable beneath Manage or a holding detail. Asset changes distinguishes
recalculated history from immutable observations captured at the shown time.
Missing FX stays explicit; neither retroactive snapshots nor closing-net-worth
claims are inferred from an ordinary foreground capture. Historical retrieval
uses the existing public data providers and preserves native currencies.
