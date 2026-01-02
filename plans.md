# Assetta – V1 Execution Plan (Updated)

This plan reflects the actual execution order and locked decisions agreed during development.
It supersedes any earlier versions.

## Milestone 1 – Foundation
- App shell
- Workspace model
- Local database (GRDB)
- SQLCipher encryption with Keychain keys
- CloudKit sync scaffolding
- Onboarding snapshot

## Milestone 2 – Accounts & Transactions
- Account types (current, credit, savings, investment)
- Manual transaction entry
- Transfers and card payments
- Edit/delete transactions
- Linked-transaction deletion blocked

## Milestone 3 – Budget Foundations
- Categories
- Planned monthly income (IncomePlan)
- Monthly budget allocations (BudgetMonth + BudgetCategoryPlan)
- Overspend visibility (no recovery yet)
- Unallocated income allowed and visible
- Actual vs planned income variance explicit

## Milestone 4 – Savings & Recovery Semantics
- Savings contribution and withdrawal semantics
- Savings accounts treated as destinations, not categories
- Recovery schedules for:
  - overspend
  - savings-funded withdrawals or trips
- Application of recovery over 1–3 future months
- Investment account scaffolding and valuation snapshots

## Milestone 5 – UI & UX Build
- Navigation and layout refinement (macOS + iPadOS)
- Budget and savings visual design
- Dedicated Savings UI section
- End-of-month review UX
- Optional prompt to move unallocated income to savings
- No AI in this milestone

## Milestone 6 – Imports
- CSV import
- PDF attachment
- Import confirmation flows

## Milestone 7 – Statement Reconciliation
- PDF extraction (template-based initially)
- Match / new / conflict review

## Milestone 8 – AI Integration
- Finance Pack generation
- AgentContext persistence
- Chat and analysis skills
