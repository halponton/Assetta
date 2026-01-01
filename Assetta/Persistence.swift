import Foundation
import GRDB

enum PersistenceError: Error {
    case databaseUnavailable
    case transactionIsLinked
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

    static func updateTransaction(id: String, date: Date, amountMajor: Decimal, type: Transaction.TransactionType, notes: String?) throws {
        guard let dbQueue = dbQueue else { throw PersistenceError.databaseUnavailable }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        // Convert major to minor units (2 decimal places)
        let amountMinor = (amountMajor * 100).rounded(0)
        let minorInt = NSDecimalNumber(decimal: amountMinor).int64Value

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE \"transaction\" SET date = ?, amount_minor = ?, type = ?, notes = ? WHERE id = ?",
                arguments: [dateString, minorInt, type.rawValue, notes, id]
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
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
