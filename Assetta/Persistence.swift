import Foundation
import GRDB

enum PersistenceError: Error {
    case databaseUnavailable
    case transactionIsLinked
    case categoryInUse
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
            // Prevent deleting categories that are referenced by transactions
            let referencingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \"transaction\" WHERE category_id = ?",
                arguments: [id]
            ) ?? 0
            if referencingCount > 0 {
                throw PersistenceError.categoryInUse
            }

            try db.execute(
                sql: "DELETE FROM category WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: Transactions
    static func listTransactions(accountId: String) throws -> [Transaction] {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        return try dbQueue.read { db in
            try Transaction.fetchAll(db, sql: "SELECT * FROM \"transaction\" WHERE account_id = ? ORDER BY date DESC, created_at DESC", arguments: [accountId])
        }
    }

    static func createTransaction(accountId: String, date: Date, amountMajor: Decimal, type: Transaction.TransactionType, notes: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        // Convert major to minor units (2 decimal places)
        let amountMinor = (amountMajor * 100).rounded(0)
        let minorInt = NSDecimalNumber(decimal: amountMinor).int64Value

        let tx = Transaction(accountId: accountId, date: dateString, amountMinor: minorInt, type: type, notes: notes)
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

        // Enforce category applicability: only for purchase and fees_interest
        let effectiveCategoryId: String? = (type == .purchase || type == .fees_interest) ? categoryId : nil

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
        let discretionaryCapacity = plan.plannedAmountMinor - plannedObligations
        let unallocatedDiscretionary = discretionaryCapacity - discretionaryBudgeted
        return (plan.plannedAmountMinor, plannedObligations, discretionaryBudgeted, discretionaryCapacity, unallocatedDiscretionary)
    }

    /// Clears an obligation amount by deleting the row for the given category in the month.
    static func clearObligationAmount(forMonth month: String, categoryId: String) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let bm = try fetchOrCreateBudgetMonth(forMonth: month)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM obligation_plan WHERE budget_month_id = ? AND category_id = ?", arguments: [bm.id, categoryId])
        }
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
