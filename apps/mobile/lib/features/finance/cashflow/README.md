# Cashflow Read Model

`features/finance/cashflow` owns the derived cash-flow projection over the ledger.

The ledger (`JournalEntry` + `Posting`) remains the only persisted source of
truth. Cash-flow rows are classified from postings and accounts at read time,
then aggregated into period summaries for cashflow pages, dividend surfaces,
dashboard cards, and AI tools. This module must not introduce a parallel
cash-flow table; future planned transactions belong to the recurring
transaction engine.

The dividend resilience report is also a read model over this ledger. It uses
rolling recorded cash flows for income growth, drawdown, concentration, tax
retention, and coverage. Per-share corporate actions are optional evidence for
change attribution; missing evidence stays explicitly combined. It is not a
security-selection backtest and must not infer historical payments that were
not recorded.

Module boundaries:

- `domain/` contains pure models, classification rules, and aggregation.
- `data/` adapts Riverpod streams and isolate execution to the pure domain.
- `ui/` is reserved for later presentation work.
