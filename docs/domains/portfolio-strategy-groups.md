# Portfolio Strategy Groups

Status: active FinanceOS architecture.

## Model

Portfolio planning is split into four independent concepts:

1. `InvestmentPortfolio` is the identity and ownership scope. It can link to a
   goal, but does not contain strategy-specific fields.
2. `PortfolioStrategyConfig` is an open, versioned module configuration.
   Built-in modules are `index_core`, `dividend_income`, and `options_income`;
   new modules register a stable string identifier and a typed codec.
3. `PortfolioRebalanceGroup` owns capital policy. Its portfolio weight is
   stored in basis points, its internal allocation is normalized to 100%, and
   its transfer policy is bidirectional, inflows-only, or isolated.
4. `PortfolioCapitalAssignment` gives a whole/partial lot or a fixed cash
   amount exactly one capital-owning group. Strategy overlays reference a
   group and never own the same capital again.

This separation keeps goals as “why”, strategies as “how”, and groups as
“which capital and under what movement policy”.

## Aggregate invariants

- Active group target weights for a portfolio sum to exactly 10,000 basis
  points.
- Every group internal target sums to 100%.
- A whole-lot assignment cannot overlap another assignment. Partial lot
  assignments cannot exceed the open lot quantity.
- A capital-owning strategy points to its own group. An overlay points to an
  existing group and creates no capital assignment.
- Strategy payloads are decoded by their registered versioned codec. Unknown
  strategy identifiers remain lossless opaque values.

The repository changes group weights and related strategy/group rows inside
one transaction and emits one sync row per changed aggregate member.

## Rebalance flow

Rebalancing is deliberately two-stage:

1. Sum the exclusive group snapshots, compare each group’s actual portfolio
   weight with its target and drift band, then match eligible surplus groups
   with eligible deficit groups. Transfer policies are applied at this stage.
2. Run the existing allocation engine independently inside every group using
   only that group’s securities and assigned cash.

The result contains explicit group decisions, blocked-policy explanations,
capital-transfer recommendations, and one executable internal plan per group.
Execution continues to consume one internal plan at a time, so group
coordination does not leak into trade-entry contracts.

## Persistence and sync

The FinanceOS-owned tables are:

- `investment_portfolios`
- `portfolio_strategy_configs`
- `portfolio_rebalance_groups`
- `portfolio_capital_assignments`

All sync through the existing `fin:` row-state boundary. The former
lot-membership table and closed portfolio strategy enum are intentionally not
part of this model.
