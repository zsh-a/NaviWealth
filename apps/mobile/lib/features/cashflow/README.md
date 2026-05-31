# Cashflow Read Model

`features/cashflow` owns the derived cash-flow projection over the ledger.

The ledger (`JournalEntry` + `Posting`) remains the only persisted source of
truth. Cash-flow rows are classified from postings and accounts at read time,
then aggregated into period summaries for cashflow pages, dividend surfaces,
dashboard cards, and AI tools. This module must not introduce a parallel
cash-flow table; future planned transactions belong to the recurring
transaction engine.

Module boundaries:

- `domain/` contains pure models, classification rules, and aggregation.
- `data/` adapts Riverpod streams and isolate execution to the pure domain.
- `ui/` is reserved for later presentation work.
