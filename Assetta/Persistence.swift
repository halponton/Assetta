import Foundation
import GRDB

enum PersistenceError: Error {
    case databaseUnavailable
    case transactionIsLinked
    case categoryInUse
    case partialPairOperationNotAllowed
    case invalidRecoverySchedule
}

struct Persistence {
    static var dbQueue: DatabaseQueue? { DatabaseManager.shared.dbQueue }

    // MARK: Workspace
    static func currentWorkspaceId() throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            if let id = try Int64.fetchOne(db, sql: "SELECT id FROM workspace ORDER BY id LIMIT 1") {
                return id
            } else {
                throw PersistenceError.databaseUnavailable
            }
        }
    }

    // MARK: Accounts
    static func listAccounts() throws -> [Account] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Account.fetchAll(db, sql: "SELECT * FROM account ORDER BY name COLLATE NOCASE")
        }
    }

    static func createAccount(name: String, type: Account.AccountType, institution: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        let account = Account(workspaceId: workspaceId, name: name, type: type, institution: institution)
        try dbQueue.write { db in
            try account.insert(db)
        }
    }

    // MARK: Savings Helpers
    /// Lists all savings accounts for the current workspace.
    static func listSavingsAccounts() throws -> [Account] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        return try dbQueue.read { db in
            try Account.fetchAll(db, sql: "SELECT * FROM account WHERE workspace_id = ? AND type = 'savings' ORDER BY name COLLATE NOCASE", arguments: [workspaceId])
        }
    }

    /// Computes the current savings balance for a specific savings account by summing contributions and withdrawals.
    /// Balance = SUM(savings_contribution) - SUM(savings_withdrawal)
    static func computeSavingsBalance(accountId: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(CASE 
                    WHEN t.type = 'savings_contribution' THEN t.amount_minor
                    WHEN t.type = 'savings_withdrawal' THEN -t.amount_minor
                    ELSE 0 END), 0)
                FROM "transaction" t
                WHERE t.account_id = ?
            """, arguments: [accountId]) ?? 0
        }
    }

    /// Computes the total savings balance across all savings accounts in the current workspace.
    static func computeTotalSavingsBalanceForWorkspace() throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(CASE 
                    WHEN t.type = 'savings_contribution' THEN t.amount_minor
                    WHEN t.type = 'savings_withdrawal' THEN -t.amount_minor
                    ELSE 0 END), 0)
                FROM "transaction" t
                JOIN account a ON a.id = t.account_id
                WHERE a.workspace_id = ? AND a.type = 'savings'
            """, arguments: [workspaceId]) ?? 0
        }
    }

    /// Creates a paired savings contribution transaction pair atomically.
    /// - fromCurrentAccountId: the source (current account) with a transfer type and negative amount
    /// - toSavingsAccountId: the destination savings account with a savings_contribution type and positive amount
    /// - notes are applied to both transactions.
    static func createSavingsContributionPair(date: Date, amountMajor: Decimal, fromCurrentAccountId: String, toSavingsAccountId: String, notes: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        let amountMinorDecimal = (amountMajor * 100).rounded(0)
        let amountMinor = NSDecimalNumber(decimal: amountMinorDecimal).int64Value

        try dbQueue.write { db in
            var transferTx = Transaction(accountId: fromCurrentAccountId, date: dateString, amountMinor: -amountMinor, type: .transfer, categoryId: nil, notes: notes)
            var contributionTx = Transaction(accountId: toSavingsAccountId, date: dateString, amountMinor: amountMinor, type: .savings_contribution, categoryId: nil, notes: notes)

            try transferTx.insert(db)
            try contributionTx.insert(db)

            transferTx.linkedTransactionId = contributionTx.id
            contributionTx.linkedTransactionId = transferTx.id

            try transferTx.update(db)
            try contributionTx.update(db)
        }
    }

    /// Creates a paired savings withdrawal transaction pair atomically.
    /// - fromSavingsAccountId: source savings account, type savings_withdrawal, negative amount
    /// - toCurrentAccountId: destination current account, type transfer, positive amount
    /// - notes applied to both transactions.
    static func createSavingsWithdrawalPair(date: Date, amountMajor: Decimal, fromSavingsAccountId: String, toCurrentAccountId: String, notes: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        let amountMinorDecimal = (amountMajor * 100).rounded(0)
        let amountMinor = NSDecimalNumber(decimal: amountMinorDecimal).int64Value

        try dbQueue.write { db in
            var withdrawalTx = Transaction(accountId: fromSavingsAccountId, date: dateString, amountMinor: -amountMinor, type: .savings_withdrawal, categoryId: nil, notes: notes)
            var transferTx = Transaction(accountId: toCurrentAccountId, date: dateString, amountMinor: amountMinor, type: .transfer, categoryId: nil, notes: notes)

            try withdrawalTx.insert(db)
            try transferTx.insert(db)

            withdrawalTx.linkedTransactionId = transferTx.id
            transferTx.linkedTransactionId = withdrawalTx.id

            try withdrawalTx.update(db)
            try transferTx.update(db)
        }
    }

    /// Creates a paired savings movement (contribution or withdrawal) by delegating to the specific pair creators.
    static func createPairedSavingsMovement(savingsAccountId: String, currentAccountId: String, date: Date, amountMajor: Decimal, isContribution: Bool) throws {
        if isContribution {
            try createSavingsContributionPair(date: date, amountMajor: amountMajor, fromCurrentAccountId: currentAccountId, toSavingsAccountId: savingsAccountId, notes: nil)
        } else {
            try createSavingsWithdrawalPair(date: date, amountMajor: amountMajor, fromSavingsAccountId: savingsAccountId, toCurrentAccountId: currentAccountId, notes: nil)
        }
    }

    /// Updates a paired savings movement given one transaction ID.
    /// Throws if the transaction is not part of a linked pair.
    /// Updates date, amount, and notes for both transactions atomically.
    static func updatePairedSavingsMovement(pairMemberId: String, date: Date, amountMajor: Decimal, notes: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        let amountMinorDecimal = (amountMajor * 100).rounded(0)
        let amountMinor = NSDecimalNumber(decimal: amountMinorDecimal).int64Value

        try dbQueue.write { db in
            guard var tx = try Transaction.fetchOne(db, key: pairMemberId) else {
                throw PersistenceError.databaseUnavailable
            }
            guard let linkedId = tx.linkedTransactionId else {
                throw PersistenceError.partialPairOperationNotAllowed
            }
            guard var linkedTx = try Transaction.fetchOne(db, key: linkedId) else {
                throw PersistenceError.partialPairOperationNotAllowed
            }

            // Determine pair type by types present
            // Valid pairs:
            // 1) transfer (negative) + savings_contribution (positive)
            // 2) savings_withdrawal (negative) + transfer (positive)

            let types = Set([tx.type, linkedTx.type])
            if types == Set([.transfer, .savings_contribution]) {
                // Find which is which
                if tx.type == .transfer {
                    tx.amountMinor = -amountMinor
                    linkedTx.amountMinor = amountMinor
                } else {
                    tx.amountMinor = amountMinor
                    linkedTx.amountMinor = -amountMinor
                }
            } else if types == Set([.savings_withdrawal, .transfer]) {
                if tx.type == .savings_withdrawal {
                    tx.amountMinor = -amountMinor
                    linkedTx.amountMinor = amountMinor
                } else {
                    tx.amountMinor = amountMinor
                    linkedTx.amountMinor = -amountMinor
                }
            } else {
                throw PersistenceError.partialPairOperationNotAllowed
            }

            tx.date = dateString
            linkedTx.date = dateString
            tx.notes = notes
            linkedTx.notes = notes

            try tx.update(db)
            try linkedTx.update(db)
        }
    }

    /// Deletes a paired savings movement given one transaction ID.
    /// Throws if the transaction is not part of a linked pair.
    static func deletePairedSavingsMovement(pairMemberId: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }

        try dbQueue.write { db in
            guard let tx = try Transaction.fetchOne(db, key: pairMemberId) else {
                throw PersistenceError.databaseUnavailable
            }
            guard let linkedId = tx.linkedTransactionId else {
                throw PersistenceError.partialPairOperationNotAllowed
            }

            try db.execute(
                sql: "DELETE FROM \"transaction\" WHERE id IN (?, ?)",
                arguments: [pairMemberId, linkedId]
            )
        }
    }

    // MARK: Categories
    static func listCategories() throws -> [Category] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        return try dbQueue.read { db in
            try Category.fetchAll(db, sql: "SELECT * FROM category WHERE workspace_id = ? ORDER BY sort_order ASC, name COLLATE NOCASE ASC", arguments: [workspaceId])
        }
    }

    static func createCategory(name: String, isDiscretionary: Bool) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        try dbQueue.write { db in
            // Determine next sort_order within workspace
            let nextOrder = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM category WHERE workspace_id = ?", arguments: [workspaceId])) ?? 0
            let cat = Category(workspaceId: workspaceId, name: name, isSystem: false, isDiscretionary: isDiscretionary, sortOrder: nextOrder)
            try cat.insert(db)
        }
    }

    static func deleteCategory(id: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        try dbQueue.write { db in
            // Prevent deleting categories that are referenced anywhere (transactions, budget plans, obligations)
            let txCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \"transaction\" WHERE category_id = ?",
                arguments: [id]
            ) ?? 0
            let budgetPlanCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM budget_category_plan WHERE category_id = ?",
                arguments: [id]
            ) ?? 0
            let obligationCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM obligation_plan WHERE category_id = ?",
                arguments: [id]
            ) ?? 0
            if txCount > 0 || budgetPlanCount > 0 || obligationCount > 0 {
                throw PersistenceError.categoryInUse
            }

            do {
                try db.execute(
                    sql: "DELETE FROM category WHERE id = ?",
                    arguments: [id]
                )
            } catch {
                // If a FK constraint still exists (race or missed pre-check), surface a friendly error
                throw PersistenceError.categoryInUse
            }
        }
    }

    // MARK: Transactions
    static func listTransactions(accountId: String) throws -> [Transaction] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Transaction.fetchAll(db, sql: "SELECT * FROM \"transaction\" WHERE account_id = ? ORDER BY date DESC, created_at DESC", arguments: [accountId])
        }
    }

    static func createTransaction(accountId: String, date: Date, amountMajor: Decimal, type: Transaction.TransactionType, notes: String?, categoryId: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        // Convert major to minor units (2 decimal places)
        let amountMinor = (amountMajor * 100).rounded(0)
        let minorInt = NSDecimalNumber(decimal: amountMinor).int64Value

        // Enforce category applicability: only for purchase and fees_interest. Others must be nil.
        let effectiveCategoryId: String? = (type == .purchase || type == .fees_interest) ? categoryId : nil

        let tx = Transaction(accountId: accountId, date: dateString, amountMinor: minorInt, type: type, categoryId: effectiveCategoryId, notes: notes)
        try dbQueue.write { db in
            try tx.insert(db)
        }
    }

    static func updateTransaction(id: String, date: Date, amountMajor: Decimal, type: Transaction.TransactionType, notes: String?, categoryId: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        // Convert major to minor units (2 decimal places)
        let amountMinor = (amountMajor * 100).rounded(0)
        let minorInt = NSDecimalNumber(decimal: amountMinor).int64Value

        // Enforce category applicability: only allowed for purchase and fees_interest.
        // Savings and all other movement types must never have a category.
        let effectiveCategoryId: String?
        if type == .purchase || type == .fees_interest {
            effectiveCategoryId = categoryId
        } else {
            effectiveCategoryId = nil
        }

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE \"transaction\" SET date = ?, amount_minor = ?, type = ?, category_id = ?, notes = ? WHERE id = ?",
                arguments: [dateString, minorInt, type.rawValue, effectiveCategoryId, notes, id]
            )
        }
    }

    static func deleteTransaction(id: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        try dbQueue.write { db in
            // Pre-check if the transaction itself has a linked_transaction_id
            let linkedTxId: String? = try String.fetchOne(db, sql: "SELECT linked_transaction_id FROM \"transaction\" WHERE id = ?", arguments: [id])
            if linkedTxId != nil {
                throw PersistenceError.transactionIsLinked
            }

            // Pre-check if any other transaction references this one via linked_transaction_id
            let referencingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \"transaction\" WHERE linked_transaction_id = ?",
                arguments: [id]
            ) ?? 0
            if referencingCount > 0 {
                throw PersistenceError.transactionIsLinked
            }

            try db.execute(
                sql: "DELETE FROM \"transaction\" WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Counts all transactions in the database.
    static func countAllTransactions() throws -> Int {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"transaction\"") ?? 0
        }
    }

    /// Counts transactions that reference a given category id.
    static func countTransactionsReferencingCategory(categoryId: String) throws -> Int {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"transaction\" WHERE category_id = ?", arguments: [categoryId]) ?? 0
        }
    }

    /// Deletes all transactions. DEBUG/DANGEROUS.
    static func deleteAllTransactions() throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM \"transaction\"")
        }
    }

    // MARK: Debug Helpers for Plans
    /// Counts all discretionary budget plan rows.
    static func countAllBudgetPlans() throws -> Int {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budget_category_plan") ?? 0
        }
    }

    /// Counts all obligation plan rows.
    static func countAllObligations() throws -> Int {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM obligation_plan") ?? 0
        }
    }

    /// Deletes all budget plan rows (discretionary).
    static func deleteAllBudgetPlans() throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM budget_category_plan")
        }
    }

    /// Deletes all obligation plan rows (non-discretionary).
    static func deleteAllObligations() throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM obligation_plan")
        }
    }

    // MARK: Income Plans
    /// Fetches the IncomePlan for a given workspace and month (YYYY-MM), or creates one with zero planned amount.
    static func fetchOrCreateIncomePlan(forMonth month: String) throws -> IncomePlan {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        return try dbQueue.write { db in
            if let plan = try IncomePlan.fetchOne(db, sql: "SELECT * FROM income_plan WHERE workspace_id = ? AND month = ?", arguments: [workspaceId, month]) {
                return plan
            } else {
                let plan = IncomePlan(workspaceId: workspaceId, month: month, plannedAmountMinor: 0)
                try plan.insert(db)
                return plan
            }
        }
    }

    /// Updates or creates the IncomePlan for a given month with the provided planned amount in minor units.
    static func upsertIncomePlan(forMonth month: String, plannedAmountMinor: Int64) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        try dbQueue.write { db in
            if var plan = try IncomePlan.fetchOne(db, sql: "SELECT * FROM income_plan WHERE workspace_id = ? AND month = ?", arguments: [workspaceId, month]) {
                plan.plannedAmountMinor = plannedAmountMinor
                try plan.update(db)
            } else {
                let plan = IncomePlan(workspaceId: workspaceId, month: month, plannedAmountMinor: plannedAmountMinor)
                try plan.insert(db)
            }
        }
    }

    /// Computes the actual income for a given month (YYYY-MM) by summing income transactions within that month for the current workspace.
    static func computeActualIncome(forMonth month: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        // Sum income over all accounts in the workspace for dates within the month
        return try dbQueue.read { db in
            let start = month + "-01"
            let sum: Int64? = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(t.amount_minor), 0)
                FROM "transaction" t
                JOIN account a ON a.id = t.account_id
                WHERE a.workspace_id = ?
                  AND t.type = 'income'
                  AND t.date >= ?
                  AND t.date < date(?, '+1 month')
            """, arguments: [workspaceId, start, start])
            return sum ?? 0
        }
    }

    /// Computes the income variance = actual - planned for the given month.
    static func computeIncomeVariance(forMonth month: String) throws -> (planned: Int64, actual: Int64, variance: Int64) {
        let plan = try fetchOrCreateIncomePlan(forMonth: month)
        let actual = try computeActualIncome(forMonth: month)
        let variance = actual - plan.plannedAmountMinor
        return (plan.plannedAmountMinor, actual, variance)
    }

    // MARK: Budgeting

    /// Fetches the BudgetMonth for the current workspace and given month (YYYY-MM), creating it if missing.
    static func fetchOrCreateBudgetMonth(forMonth month: String) throws -> BudgetMonth {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        return try dbQueue.write { db in
            if let bm = try BudgetMonth.fetchOne(db, sql: "SELECT * FROM budget_month WHERE workspace_id = ? AND month = ?", arguments: [workspaceId, month]) {
                return bm
            } else {
                let bm = BudgetMonth(workspaceId: workspaceId, month: month)
                try bm.insert(db)
                return bm
            }
        }
    }

    /// Lists all BudgetCategoryPlan rows for a given BudgetMonth id.
    static func listBudgetPlans(budgetMonthId: String) throws -> [BudgetCategoryPlan] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try BudgetCategoryPlan.fetchAll(db, sql: "SELECT * FROM budget_category_plan WHERE budget_month_id = ? ORDER BY category_id", arguments: [budgetMonthId])
        }
    }

    /// Upserts a single BudgetCategoryPlan amount for a category in a given month.
    static func upsertBudgetAmount(forMonth month: String, categoryId: String, amountMinor: Int64) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        try dbQueue.write { db in
            if var row = try BudgetCategoryPlan.fetchOne(db, sql: "SELECT * FROM budget_category_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, categoryId]) {
                row.amountMinor = amountMinor
                try row.update(db)
            } else {
                let row = BudgetCategoryPlan(budgetMonthId: bm.id, categoryId: categoryId, amountMinor: amountMinor)
                try row.insert(db)
            }
        }
    }

    /// Computes the planned income, total budgeted, and unallocated for a given month.
    static func computeBudgetSummary(forMonth month: String) throws -> (plannedIncome: Int64, totalBudgeted: Int64, unallocated: Int64) {
        let plan = try fetchOrCreateIncomePlan(forMonth: month)
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        let totalBudgeted: Int64 = try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM budget_category_plan WHERE budget_month_id = ?", arguments: [bm.id]) ?? 0
        }
        let unallocated = plan.plannedAmountMinor - totalBudgeted
        return (plan.plannedAmountMinor, totalBudgeted, unallocated)
    }

    /// Computes the total budgeted amount across all categories (discretionary + obligations) for the given month (YYYY-MM).
    static func computeTotalBudgetedAllCategories(forMonth month: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        return try dbQueue.read { db in
            let discretionary: Int64 = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM budget_category_plan WHERE budget_month_id = ?", arguments: [bm.id]) ?? 0
            let obligations: Int64 = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM obligation_plan WHERE budget_month_id = ?", arguments: [bm.id]) ?? 0
            return discretionary + obligations
        }
    }

    /// Computes the sum of recovery adjustments that apply to the given month (YYYY-MM).
    /// A recovery schedule applies for months in the range [start_month, start_month + durationMonths), comparing strings lexicographically as YYYY-MM.
    static func computeRecoveryAdjustments(forMonth month: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()

        // Recovery is never retroactive: only apply to current and future months.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())
        if month < currentMonth { return 0 }

        return try dbQueue.read { db in
            // Fetch schedules that start on or before the target month for this workspace
            let schedules: [RecoverySchedule] = try RecoverySchedule.fetchAll(
                db,
                sql: "SELECT * FROM recovery_schedule WHERE workspace_id = ? AND start_month <= ?",
                arguments: [workspaceId, month]
            )
            var total: Int64 = 0
            for s in schedules {
                // Compute end month exclusive using the helper
                if let endExclusive = try addMonths(toMonth: s.startMonth, monthsToAdd: s.durationMonths) {
                    if s.startMonth <= month && month < endExclusive {
                        total += s.monthlyAdjustmentMinor
                    }
                }
            }
            return total
        }
    }

    /// Computes totals for planned income, planned obligations (non-discretionary), discretionary budgeted, discretionary capacity, and unallocated discretionary.
    static func computeBudgetAndObligationSummary(forMonth month: String) throws -> (plannedIncome: Int64, plannedObligations: Int64, discretionaryBudgeted: Int64, discretionaryCapacity: Int64, unallocatedDiscretionary: Int64) {
        let plan = try fetchOrCreateIncomePlan(forMonth: month)
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        let discretionaryBudgeted: Int64 = try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM budget_category_plan WHERE budget_month_id = ?", arguments: [bm.id]) ?? 0
        }
        let plannedObligations: Int64 = try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM obligation_plan WHERE budget_month_id = ?", arguments: [bm.id]) ?? 0
        }
        let recoveryAdjustments: Int64 = try computeRecoveryAdjustments(forMonth: month)
        let discretionaryCapacity = plan.plannedAmountMinor - plannedObligations - recoveryAdjustments
        let unallocatedDiscretionary = discretionaryCapacity - discretionaryBudgeted
        return (plan.plannedAmountMinor, plannedObligations, discretionaryBudgeted, discretionaryCapacity, unallocatedDiscretionary)
    }

    /// Convenience helper that returns the discretionary capacity after applying recovery adjustments for the given month (YYYY-MM).
    /// This does not persist anything; it derives values dynamically.
    static func computeRecoveryAdjustedDiscretionaryCapacity(forMonth month: String) throws -> Int64 {
        let summary = try computeBudgetAndObligationSummary(forMonth: month)
        return summary.discretionaryCapacity
    }

    /// Computes monthly overspend where overspend = total_actual_spend - total_budgeted.
    /// Positive overspend indicates the month is overspent.
    static func computeMonthlyOverspend(forMonth month: String) throws -> (totalBudgeted: Int64, totalActual: Int64, overspend: Int64) {
        let totalBudgeted = try computeTotalBudgetedAllCategories(forMonth: month)
        let totalActual = try computeTotalActualSpend(forMonth: month)
        let overspend = totalActual - totalBudgeted
        return (totalBudgeted, totalActual, overspend)
    }

    /// Computes the total actual spend (purchases only) across all accounts in the current workspace for the given month (YYYY-MM).
    static func computeTotalActualSpend(forMonth month: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        let start = month + "-01"
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(t.amount_minor), 0)
                FROM "transaction" t
                JOIN account a ON a.id = t.account_id
                WHERE a.workspace_id = ?
                  AND t.type = 'purchase'
                  AND t.date >= ?
                  AND t.date < date(?, '+1 month')
            """, arguments: [workspaceId, start, start]) ?? 0
        }
    }

    /// Computes actual spend for a category in a given month (YYYY-MM) across all accounts in the current workspace.
    /// Only includes transactions of type 'purchase' with matching category and date in the month.
    static func computeActualSpend(forMonth month: String, categoryId: String) throws -> Int64 {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        let start = month + "-01"
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(t.amount_minor), 0)
                FROM "transaction" t
                JOIN account a ON a.id = t.account_id
                WHERE a.workspace_id = ?
                  AND t.type = 'purchase'
                  AND t.category_id = ?
                  AND t.date >= ?
                  AND t.date < date(?, '+1 month')
            """, arguments: [workspaceId, categoryId, start, start]) ?? 0
        }
    }

    /// Returns per-category planned vs actual for all discretionary categories for the given month.
    static func plannedVsActualByCategory(forMonth month: String) throws -> [(category: Category, budgeted: Int64, actual: Int64, remaining: Int64)] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        let categories = try Persistence.listCategories().filter { $0.isDiscretionary }
        return try dbQueue.read { db in
            var result: [(Category, Int64, Int64, Int64)] = []
            for cat in categories {
                let budgeted: Int64 = try Int64.fetchOne(db, sql: "SELECT amount_minor FROM budget_category_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, cat.id]) ?? 0
                let actual = try computeActualSpend(forMonth: month, categoryId: cat.id)
                let remaining = budgeted - actual
                result.append((cat, budgeted, actual, remaining))
            }
            return result
        }
    }

    /// Clears a budgeted amount (sets to zero) by deleting the plan row for the given category in the month.
    static func clearBudgetAmount(forMonth month: String, categoryId: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM budget_category_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, categoryId])
        }
    }

    // MARK: Obligations (planned amounts for non-discretionary categories)

    /// Upserts a planned obligation amount for a non-discretionary category in the given month.
    static func upsertObligationAmount(forMonth month: String, categoryId: String, amountMinor: Int64) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        try dbQueue.write { db in
            if var row = try ObligationPlan.fetchOne(db, sql: "SELECT * FROM obligation_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, categoryId]) {
                row.amountMinor = amountMinor
                try row.update(db)
            } else {
                let row = ObligationPlan(budgetMonthId: bm.id, categoryId: categoryId, amountMinor: amountMinor)
                try row.insert(db)
            }
        }
    }

    /// Lists planned obligations for the given budget month id.
    static func listObligations(budgetMonthId: String) throws -> [ObligationPlan] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try ObligationPlan.fetchAll(db, sql: "SELECT * FROM obligation_plan WHERE budget_month_id = ? ORDER BY category_id", arguments: [budgetMonthId])
        }
    }

    /// Clears an obligation amount by deleting the row for the given category in the month.
    static func clearObligationAmount(forMonth month: String, categoryId: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM obligation_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, categoryId])
        }
    }

    // MARK: Recovery Schedules

    /// Lists all active RecoverySchedules for the current workspace, ordered by start_month and created_at.
    static func listActiveRecoverySchedules() throws -> [RecoverySchedule] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        let currentMonth: String = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: Date())
        }()
        return try dbQueue.read { db in
            try RecoverySchedule.fetchAll(db, sql: """
                SELECT * FROM recovery_schedule
                WHERE workspace_id = ?
                  AND start_month >= ?
                ORDER BY start_month ASC, created_at ASC
                """, arguments: [workspaceId, currentMonth])
        }
    }

    /// Creates a new RecoverySchedule for the current workspace.
    /// Validates:
    /// - durationMonths must be between 1 and 3 inclusive
    /// - monthlyAdjustmentMinor must be positive
    /// - startMonth must be in YYYY-MM format (basic check)
    /// - startMonth must not be in the past relative to current month
    /// - startMonth must be >= earliestStart derived from sourceType and sourceId (one month after source month)
    /// Throws PersistenceError.invalidRecoverySchedule on validation failure.
    static func createRecoverySchedule(sourceType: RecoverySchedule.SourceType, sourceId: String, startMonth: String, durationMonths: Int, monthlyAdjustmentMinor: Int64) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try currentWorkspaceId()
        // Basic validation of startMonth format (YYYY-MM)
        guard startMonth.count == 7 && startMonth.contains("-") else {
            throw PersistenceError.invalidRecoverySchedule
        }
        guard durationMonths >= 1 && durationMonths <= 3 else {
            throw PersistenceError.invalidRecoverySchedule
        }
        guard monthlyAdjustmentMinor > 0 else {
            throw PersistenceError.invalidRecoverySchedule
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"

        let currentMonth = formatter.string(from: Date())

        guard startMonth >= currentMonth else {
            throw PersistenceError.invalidRecoverySchedule
        }

        try dbQueue.write { db in
            // Derive sourceMonth based on sourceType
            let sourceMonth: String
            switch sourceType {
            case .overspend:
                if sourceId.count == 7 && sourceId.contains("-") {
                    // Treat sourceId as a YYYY-MM month string
                    sourceMonth = sourceId
                } else if let bm = try BudgetMonth.fetchOne(db, key: sourceId) {
                    // Backward compatibility: treat sourceId as BudgetMonth.id
                    sourceMonth = bm.month
                } else {
                    throw PersistenceError.invalidRecoverySchedule
                }
            case .savings_withdrawal:
                if let tx = try Transaction.fetchOne(db, key: sourceId) {
                    guard tx.type == .savings_withdrawal else {
                        throw PersistenceError.invalidRecoverySchedule
                    }
                    // tx.date is YYYY-MM-DD; get prefix 7 chars for YYYY-MM
                    let dateStr = tx.date
                    guard dateStr.count >= 7 else {
                        throw PersistenceError.invalidRecoverySchedule
                    }
                    sourceMonth = String(dateStr.prefix(7))
                } else {
                    throw PersistenceError.invalidRecoverySchedule
                }
            }

            // Compute earliestStart = sourceMonth + 1 month
            guard let earliestStart = try addMonths(toMonth: sourceMonth, monthsToAdd: 1) else {
                throw PersistenceError.invalidRecoverySchedule
            }

            guard startMonth >= earliestStart else {
                throw PersistenceError.invalidRecoverySchedule
            }

            let schedule = RecoverySchedule(
                workspaceId: workspaceId,
                sourceType: sourceType,
                sourceId: sourceId,
                startMonth: startMonth,
                durationMonths: durationMonths,
                monthlyAdjustmentMinor: monthlyAdjustmentMinor
            )
            try schedule.insert(db)
        }
    }

    /// Deletes the RecoverySchedule with the given id.
    /// Returns true if a row was deleted, false otherwise.
    static func deleteRecoverySchedule(id: String) throws -> Bool {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.write { db in
            let deletedCount = try Int.fetchOne(
                db,
                sql: "WITH del AS (DELETE FROM recovery_schedule WHERE id = ?) SELECT changes()",
                arguments: [id]
            ) ?? 0
            return deletedCount > 0
        }
    }

    // MARK: Private helpers for month math

    /// Adds months to a YYYY-MM string and returns the resulting YYYY-MM string or nil if invalid.
    private static func addMonths(toMonth month: String, monthsToAdd: Int) throws -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: month) else {
            return nil
        }
        guard let newDate = Calendar(identifier: .iso8601).date(byAdding: .month, value: monthsToAdd, to: date) else {
            return nil
        }
        return formatter.string(from: newDate)
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

