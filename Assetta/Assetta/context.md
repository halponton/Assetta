# Assetta – Project Context

This document provides the conceptual and philosophical context for Assetta.
It explains why the system is designed the way it is.

All contributors (human or AI) must internalise this context before making
architectural or behavioural decisions.

---

## What Assetta Is

Assetta is a personal finance system centred on assets, intent, and recovery.

It is designed for a user who:
- does almost all spending on credit cards
- values correctness over convenience
- wants to build wealth, not just track spend
- expects software to reflect financial reality, not obscure it

Assetta is not a gamified expense tracker.
It is a calm, factual financial instrument.

---

## Core Mental Model

### Spending vs Movement

Most money movement is not spending.

- Spending = purchases (goods and services)
- Movement = transfers, repayments, reallocations

Credit card payments are movement, not spending.
Savings and investments are stores of value, not expenses.

Budgets must reflect this reality at all times.

---

## Time Matters

Assetta reasons in months, not days.

- Budgets are monthly
- Credit cards settle previous months
- Overspend does not vanish; it is recovered deliberately
- Recovery happens over future months, not retroactively

All financial explanations must be time-aware.

---

## Overspend and Recovery

Overspend is not failure.
It is a signal.

When overspend occurs:
- it must be visible
- it must be explained
- it must be recovered intentionally

Recovery reduces future discretionary capacity.
It must never be hidden or silently absorbed.

---

## Savings and Investments

Savings and investments are not leftover money.
They are first-class goals.

Key distinctions:
- contributions vs withdrawals
- market movement vs user action
- value can change without transactions

Assetta must never moralise market volatility.

---

## Trips

Most trips are normal discretionary spending.

Only large trips explicitly funded from savings gain structural meaning.
This happens only when the user links a savings withdrawal to a trip.

Trips must never:
- automatically pull from savings
- bypass budgets by default
- distort financial reporting

---

## Onboarding Philosophy

Assetta begins with a current snapshot.

- No forced history imports
- No assumptions about past behaviour
- Ledger epoch begins 1 Jan 2026

The system reasons forward, not backward.

---

## AI in Assetta

AI is a coach and analyst, not an authority.

The AI:
- operates on a bounded Finance Pack
- does not see raw accounts unless explicitly allowed
- does not remember; memory is app-managed
- must respect previously confirmed user facts

The AI must:
- explain reasoning
- avoid repetition
- avoid assumptions
- avoid nagging

If the AI is unsure, it must ask or stay silent.

---

## Tone and Behaviour

Assetta’s tone is:
- composed
- factual
- supportive without being patronising

The system must never:
- shame spending
- celebrate market luck
- invent intent
- optimise for engagement over truth

---

## Design Implication

When in doubt:
- choose explicitness over automation
- choose transparency over cleverness
- choose user control over prediction

Assetta exists to help the user think clearly about money.
