# Portfolio Strategy Groups

Status: active FinanceOS architecture.

## Model

Portfolio planning is one capital tree with seven independent concepts:

1. `RebalanceUniverse` is the explicit denominator for a set of portfolios.
   The initial product surface creates one default universe per owner.
2. `PortfolioAllocationTarget` controls a portfolio's target weight, drift
   band, and transfer policy inside that universe.
3. `InvestmentPortfolio` is the identity and ownership scope. It can link to a
   goal, but does not contain strategy-specific fields.
4. `PortfolioStrategyTemplate` is the catalog SSOT for creation and
   presentation defaults. Built-in and user-authored templates use the same
   contract; custom kinds have stable `user:<uuid>` identifiers.
5. `PortfolioStrategyConfig` is an instantiated, open, versioned module
   configuration. Capital-owning modules point to a group; overlays point to
   a group but have no target weight.
6. `PortfolioRebalanceGroup` is the persisted capital owner behind a
   user-visible strategy. Its portfolio weight is stored in basis points, its
   internal allocation is normalized to 100%, and its transfer rule is free
   transfer, receive-funds-only, or independently managed.
7. `PortfolioCapitalAssignment` gives a whole/partial lot or a fixed cash
   amount exactly one capital-owning group. Strategy overlays reference a
   group and never own the same capital again.

This separation keeps goals as “why”, strategies as “how”, and groups as
“which capital and under what movement policy”.

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
silently changes existing targets. A non-zero portfolio must be set to 0% in
the complete plan before it can be removed.

## Rebalance flow

Rebalancing is deliberately three-stage:

1. Sum each portfolio's exclusive capital, compare portfolio actual weights
   with universe targets, and recommend eligible inter-portfolio transfers.
2. Sum the exclusive strategy snapshots, compare each strategy’s actual
   portfolio weight with its target and allowed deviation, then match eligible
   surplus strategies with eligible deficit strategies. Transfer rules are
   applied at this stage.
3. Run the allocation engine independently inside every strategy using only
   that strategy’s securities and assigned cash. The strategy’s allowed
   deviation is also the warning threshold for its internal asset plan.

Both capital levels use the same policy-aware `CapitalAllocationEngine`.
The result contains explicit portfolio and strategy decisions, blocked-policy
explanations, capital-transfer recommendations, and one executable internal
plan per strategy. Capital movements are resolved first through the asset
assignment center, because an amount alone cannot safely choose which tax lots
or cash accounts move. Internal trade execution remains locked while an
eligible portfolio or strategy transfer is pending; it unlocks after
assignments bring both capital levels inside tolerance.

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
