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
6. `PortfolioRebalanceGroup` owns strategy-level capital policy. Its portfolio
   weight is
   stored in basis points, its internal allocation is normalized to 100%, and
   its transfer policy is bidirectional, inflows-only, or isolated.
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
- A single portfolio in a universe and a single group in a portfolio are
  fixed at 100%; partial targets become meaningful only after adding a peer.
- Every group internal target sums to 100%.
- A whole-lot assignment cannot overlap another assignment. Partial lot
  assignments cannot exceed the open lot quantity.
- A capital-owning strategy points to its own group. An overlay points to an
  existing group and creates no capital assignment.
- Strategy payloads are decoded by their registered versioned codec. Unknown
  strategy identifiers remain lossless opaque values.

The repository changes portfolio or group weights and all redistributed peers
inside one transaction and emits one sync row per changed aggregate member.

## Rebalance flow

Rebalancing is deliberately three-stage:

1. Sum each portfolio's exclusive capital, compare portfolio actual weights
   with universe targets, and recommend eligible inter-portfolio transfers.
2. Sum the exclusive group snapshots, compare each group’s actual portfolio
   weight with its target and drift band, then match eligible surplus groups
   with eligible deficit groups. Transfer policies are applied at this stage.
3. Run the existing allocation engine independently inside every group using
   only that group’s securities and assigned cash.

Both capital levels use the same policy-aware `CapitalAllocationEngine`.
The result contains explicit portfolio and group decisions, blocked-policy
explanations, capital-transfer recommendations, and one executable internal
plan per group.
Execution continues to consume one internal plan at a time, so group
coordination does not leak into trade-entry contracts.

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
