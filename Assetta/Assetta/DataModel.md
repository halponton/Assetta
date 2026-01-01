# Assetta – Canonical Data Model

## Workspace
- id
- name
- type

## Account
- id
- workspace_id
- name
- type
- institution
- currency

## Transaction
- id
- account_id
- date
- amount
- type
- category_id
- trip_id
- linked_transaction_id
- notes

## Category
- id
- name
- is_system
- is_discretionary

## BudgetMonth
- id
- workspace_id
- month
- total_discretionary

## RecoverySchedule
- id
- source_type
- source_id
- start_month
- duration_months
- monthly_adjustment

## Trip
- id
- name
- start_date
- end_date

## StatementDocument
- id
- account_id
- period_start
- period_end
- file_reference

## ValuationSnapshot
- id
- account_id
- date
- value

## AgentContext
- id
- workspace_id
- summary_state
- last_updated
