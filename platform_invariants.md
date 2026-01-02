# Assetta – Platform Invariants (Updated)

These invariants are non-negotiable. All code and features must comply.

## Budgeting & Income
- Budgets are anchored to planned monthly income (IncomePlan).
- Actual income is compared to planned income; variance is explicit.
- Income variance is never silently absorbed.

## Unallocated Income
- Unallocated income is allowed and first-class.
- Unallocated income represents:
  - positive income variance, and/or
  - planned income not allocated to category budgets.
- Unallocated income must remain visible until the user explicitly acts.
- No automatic movement of unallocated income is allowed.

## Savings
- Savings are not categories.
- Savings movements are represented via:
  - savings_contribution
  - savings_withdrawal
- Savings contributions do not count as spending.
- Savings logic must exist before any prompting or automation.

## Prompting & Automation
- Any prompt to move unallocated income to savings:
  - must be optional
  - must be explicit
  - must be deferred until after:
    - savings semantics are implemented, and
    - UI/UX build phase is complete
- No automatic transfers or sweeps are allowed.

## Overspend
- Overspend must be explicit and visible.
- Overspend must not be automatically resolved.
- Recovery logic must be explicit and time-bounded.

## Ordering
- UI/UX polish must precede Imports and AI.
- AI must never compensate for missing or unclear UI or semantics.
