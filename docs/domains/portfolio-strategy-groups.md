# Portfolio Allocation Tree

Status: active FinanceOS architecture.

## Model

Portfolio planning is presented as one allocation tree:

1. **Investment plan** is the 100% denominator across portfolios.
2. **Portfolio** expresses one investment purpose and its share of the plan.
3. **Strategy sleeve** owns a share of one portfolio, an allowed drift, a
   transfer policy, and an internal asset target.
4. **Asset target** is a category or concrete security inside a sleeve.
5. **Rule** is versioned behavior attached to a sleeve. It never owns capital.
6. **Included asset** gives a whole/partial lot or fixed cash amount exactly
   one sleeve.

The application exposes these concepts through `PortfolioAllocationTree`,
`AllocationNode`, `StrategyAttachment`, and `CapitalInclusion`. Persistence
entities are implementation details joined by the tree provider; UI and
workflow code must not independently reconstruct universes, targets, groups,
strategy configs, and assignments.

The terminology is intentional: goals are “why”, portfolios are “for what”,
sleeves are “how capital is allocated”, rules are “additional behavior”, and
included assets are “what the sleeve currently owns”.

## Interaction contract

- `/wealth/portfolio` is the state-first investment plan overview. Each
  portfolio card shows actual versus target weight and drift state.
- `/wealth/portfolio/:portfolioId/studio` is the only deep configuration
  surface. It has Overview, Structure, Assets, and Rules sections.
- Creating a portfolio or sleeve is a short modal action. Configuration,
  inspection, and navigation remain on full pages.
- Portfolio and sleeve weights use the same complete-sibling allocation
  editor. Advanced drift and transfer policy controls remain progressive
  disclosure.
- Rebalancing is entered from the plan overview or portfolio studio and is
  shown in order: portfolio transfers, sleeve allocation, sleeve assets, then
  executable trades.
- UI copy says “included assets” and “rules”; it does not expose
  “assignments”, “rebalance groups”, “capital owners”, or “overlays”.

## Aggregate invariants

- Active group target weights for a portfolio sum to exactly 10,000 basis
  points.
- Active portfolio target weights for a universe sum to exactly 10,000 basis
  points.
- A single portfolio in a universe and a single strategy in a portfolio are
  fixed at 100%; partial targets become meaningful only after adding a peer.
- Every group internal target sums to 100%.
- A whole-lot assignment cannot overlap another assignment. Partial lot
  assignments cannot exceed the open lot quantity.
- A capital-owning strategy points to its own group. An overlay points to an
  existing group and creates no capital assignment.
- Strategy payloads are decoded by their registered versioned codec. Unknown
  strategy identifiers remain lossless opaque values.

Portfolio and strategy shares are edited as complete sibling sets. The
repository validates that the submitted set exactly matches the active set,
totals 10,000 basis points, saves every member in one transaction, and emits
one sync row per member. A newly added peer starts at 0% so creation never
silently changes existing targets.

Strategy configs and capital groups are independent instances with UUID
identities; `kind` identifies their reusable template and is not an instance
key. A portfolio may therefore contain several instances of the same
strategy kind.

Removal is a transfer operation rather than a manual zero-weight precondition.
The user chooses a receiving portfolio strategy, then the repository moves the
source target weight and capital assignments before tombstoning the source
aggregate in the same transaction. Removing a capital strategy also
tombstones its mounted overlays. Every portfolio must retain at least one
capital-owning strategy. An overlay may be removed independently because it
owns no capital. Accounting records are never rewritten by these operations.

## Rebalance flow

Rebalancing is deliberately three-stage before execution:

1. Sum each portfolio's exclusive capital, compare portfolio actual weights
   with universe targets, and recommend eligible inter-portfolio transfers.
2. Sum the exclusive sleeve snapshots, compare each sleeve’s actual portfolio
   weight with its target and allowed deviation, then match eligible surplus
   sleeves with eligible deficit sleeves. Transfer rules are
   applied at this stage.
3. Run the allocation engine independently inside every sleeve using only
   that sleeve’s securities and included cash. The sleeve’s allowed
   deviation is also the warning threshold for its internal asset plan.

Both capital levels use the same policy-aware `CapitalAllocationEngine`.
The result contains explicit portfolio and strategy decisions, blocked-policy
explanations, capital-transfer recommendations, and one executable internal
plan per sleeve. Capital movements are resolved by changing included assets,
because an amount alone cannot safely choose which tax lots or cash accounts
move. Internal trade execution remains locked while an eligible portfolio or
sleeve transfer is pending; it unlocks after inclusions bring both capital
levels inside tolerance.

## Persistence and sync

The FinanceOS-owned tables are:

- `investment_portfolios`
- `portfolio_strategy_templates`
- `rebalance_universes`
- `portfolio_allocation_targets`
- `portfolio_strategy_configs`
- `portfolio_rebalance_groups`
- `portfolio_capital_assignments`

All sync through the existing `fin:` row-state boundary. The former
lot-membership table and closed portfolio strategy enum are intentionally not
part of this model.
