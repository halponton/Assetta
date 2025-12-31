# Assetta – Platform Invariants

These invariants are non-negotiable. All code, architecture, and AI behaviour
must conform to them. If a feature conflicts with an invariant, the feature
must be redesigned or rejected.

## 1. Core Philosophy

Assetta is an asset- and intent-focused personal finance application.
It is not a simple expense tracker.

The system must prioritise:
- correctness over convenience
- explicit user intent over inference
- explainability over automation
- local-first data ownership

## 2. Platforms

- Single SwiftUI codebase
- macOS + iPadOS first-class
- iPhone is deferred but must not be blocked by architectural choices

## 3. Data Ownership & Storage

- All financial data is stored locally on-device
- A local database is the source of truth
- Sync is additive and conflict-resolving, not authoritative

### Sync
- Sync uses iCloud / CloudKit (private database)
- Sync must work offline-first
- Conflicts must be deterministic and explainable

## 4. Security

- App must support Face ID / Touch ID where available
- Sensitive data must be encrypted at rest
- Encryption keys must never leave the device
- AI features must never implicitly transmit raw financial data

## 5. Ledger Epoch

- Assetta tracks all spending from 1 Jan 2026 onwards
- No historical backfill is required or assumed
- Onboarding captures a current snapshot only

## 6. Transaction Semantics (Critical)

Allowed transaction types:

- purchase
- income
- transfer
- card_payment (subtype of transfer)
- savings_contribution
- savings_withdrawal
- investment_contribution
- investment_withdrawal
- fees_interest

Rules:
- Purchases are the ONLY transactions that count against budgets
- Credit card payments must NEVER count as spending
- Transfers are budget-neutral
- Savings and investment movements affect net worth, not budgets

## 7. Credit Cards

- Credit cards are primary spending instruments
- Monthly credit card payments settle prior-period purchases
- Budgeting is based on purchase date, not payment date

## 8. Budgeting Rules

- Budgets are monthly only
- Budgets apply to personal workspace only

### Budget Recovery
- Overspend can be smoothed over 1–3 future months
- Recovery reduces future discretionary budgets
- Recovery is explicit and visible to the user

## 9. Savings & Investments

- Savings and investments are first-class
- Investment value may change without transactions
- Valuation snapshots must be supported
- Performance must separate contributions, withdrawals, and market movement

## 10. Trips

- Trips are optional organisational structures
- Most trips are funded from discretionary spend

### Savings-funded trips
- Only occur when a savings_withdrawal is explicitly linked to a trip
- Such linkage may create a recovery schedule
- Recovery behaves like budget smoothing

## 11. AI Boundary

- AI is advisory, not authoritative
- AI operates on a bounded Finance Pack
- Agent context is persisted locally
- Models must never be relied upon for memory

## 12. Offline Mode

- Assetta must function fully offline except for AI inference

## 13. Backups

- A backup must be created after every successful data mutation
