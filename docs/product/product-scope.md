# NaviWealth Product Scope (NSH Client)

Status: active product SSOT for the NSH client.

Last reviewed: 2026-11-13.

## Document Contract

Owns what the NSH client is for, which features exist, and which are
deliberately absent. [ADR 0002](../architecture/adr/0002-personal-local-scope.md)
records the architectural consequences; the
[roadmap](../roadmap/roadmap-lifeos.md) owns delivery order. The frozen
Flutter client's feature inventory is not a parity target.

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
3. AI only turns a photo or screenshot into a draft. The user confirms before
   anything is saved. No chat, named agents, proposals, or background agents.
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

Decided 2026-11-13; screens in `.impeccable/mocks/2026-11-13-lifeos-ia/`.

- A floating tab bar beside one capture button. The capture sheet holds
  every way to record: log a meal from a photo (the system picker also takes
  photos), weight, favorites, manual meal, and later a transaction and a
  receipt. No record type gets its own permanent button.
- Recognition never blocks. The owner may leave the review page while a
  photo is analyzed; an unconfirmed result becomes a draft pinned on Today
  and in Records. Nothing is saved before confirmation.
- Today shows today. Past days are reached in Records; logging for another
  day changes the date on the review page.
- Today keeps one layout from health-only to finance: the summary card shows
  intake now and spending beside it once the ledger exists.

## Kept Features

### Ledger

- Accounts with balances; a liability is an account with a negative balance.
- Transactions: expense, income, transfer between own accounts; category,
  account, note. Manual entry is a bottom sheet.
- Statement import for the existing Alipay, WeChat XLSX and CMB credit-card
  parsers, with duplicate detection and per-row confirmation. Reuse the
  statement corpus fixtures.
- Receipt or payment-screenshot recognition into a transaction draft through
  the owner's own model account.
- One optional monthly budget total. No per-category budgets.

### Holdings (detail required)

- Securities from the existing catalog shipped via GitHub Releases.
- Trades: buy, sell, dividend, fee. Positions, average cost, realized and
  unrealized gain are derived from trades.
- Quote refresh from one market-data provider, on demand and at app start;
  FX conversion to the base currency.
- Allocation by asset class and currency on the Assets tab.

### Health

- Meal logging as in the current NSH client: photo recognition with consent,
  editable consumed grams, local catalog nutrition, manual entry.
- Favorites: a saved meal kept as a favorite (its own copy, photo shared)
  logs again on any day with one tap and Undo, or after adjusting. It
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
  daily foreground backups and manual backup/restore, excluding photos and
  credentials. System-picker local export and photo archives remain planned.
- A one-time import of kept records from the Flutter client.

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

Removed data is not lost: before Flutter retires, export its full backup
and keep it as an archive file.

## Records In Scope

Account, Transaction, Category, Budget (optional), Security, Trade, Quote,
Meal (with food snapshots and local photos), Favorite meal, Weight, Garmin daily summary,
Review note. Positions and net worth are derived and not stored as truth.
