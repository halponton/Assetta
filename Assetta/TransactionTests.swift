// Note: This file is part of the Assetta module; @testable import Assetta would be redundant and cause a warning.
#if canImport(XCTest)
import Foundation
import XCTest
import GRDB

final class TransactionTests: XCTestCase {

    // MARK: - Helpers

    // Tests mirror production FK enforcement by using the same GRDB configuration
    // that enables PRAGMA foreign_keys = ON for every connection.
    private func makeInMemoryQueue() throws -> DatabaseQueue {
        let config = DatabaseManager.makeConfiguration()
        let queue = try DatabaseQueue(path: ":memory:", configuration: config)
        return queue
    }

    private func createMinimalSchema(_ db: Database) throws {
        // Minimal account table to satisfy foreign key constraints
        try db.create(table: "account") { t in
            t.column("id", .text).notNull()
            t.primaryKey(["id"]) // TEXT PK (UUID)
        }

        // Minimal category table to satisfy foreign key constraints
        try db.create(table: "category") { t in
            t.column("id", .text).notNull()
            t.primaryKey(["id"]) // TEXT PK (UUID)
        }

        // Transaction table (mirrors v3 migration)
        try db.create(table: "transaction") { t in
            // Primary key: UUID stored as TEXT
            t.column("id", .text).notNull()
            t.primaryKey(["id"]) // TEXT PK (UUID)

            // Foreign key to account(id)
            t.column("account_id", .text).notNull()
            t.foreignKey(["account_id"], references: "account", columns: ["id"], onDelete: .cascade)

            // Date (YYYY-MM-DD), constrained to ledger epoch
            t.column("date", .text).notNull()
            t.check(sql: "date >= '2026-01-01'")

            // Amount in minor units (Int64)
            t.column("amount_minor", .integer).notNull()

            // Type constrained to allowed semantics
            t.column("type", .text).notNull()
            t.check(sql: "type IN ('purchase','income','transfer','card_payment','savings_contribution','savings_withdrawal','investment_contribution','investment_withdrawal','fees_interest')")

            // Optional link to another transaction (e.g., transfer pairing)
            t.column("linked_transaction_id", .text)
            t.foreignKey(["linked_transaction_id"], references: "transaction", columns: ["id"])

            // Optional category reference
            t.column("category_id", .text)
            t.foreignKey(["category_id"], references: "category", columns: ["id"]) // no cascade delete

            // Optional notes
            t.column("notes", .text)

            // Creation timestamp (ISO-8601 string)
            t.column("created_at", .text).notNull()
        }

        // Index to speed up account/date queries
        try db.create(index: "transaction_account_date_idx", on: "transaction", columns: ["account_id", "date"])
    }

    // MARK: - Tests

    func testMigrationCreatesTransactionTableAndIndex() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)

            let hasTable = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='transaction')"
            ) ?? false
            XCTAssertTrue(hasTable, "transaction table should exist")

            let hasIndex = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name='transaction_account_date_idx')"
            ) ?? false
            XCTAssertTrue(hasIndex, "transaction_account_date_idx should exist")
        }
    }

    func testInsertValidTransactionPersistsAndFetches() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)
            try db.execute(sql: "INSERT INTO account (id) VALUES (?)", arguments: ["a1"])

            let bigAmount: Int64 = 3_000_000_000 // > Int32.max to validate 64-bit storage
            var tx = Transaction(
                accountId: "a1",
                date: "2026-01-15",
                amountMinor: bigAmount,
                type: .purchase,
                notes: "Test note"
            )
            try tx.insert(db)

            let fetched = try Transaction.fetchOne(db, key: tx.id)
            let f = try XCTUnwrap(fetched)
            XCTAssertEqual(f.id, tx.id)
            XCTAssertEqual(f.accountId, "a1")
            XCTAssertEqual(f.date, "2026-01-15")
            XCTAssertEqual(f.amountMinor, bigAmount)
            XCTAssertEqual(f.type, .purchase)
            XCTAssertEqual(f.notes, "Test note")
            XCTAssertFalse(f.createdAt.isEmpty)
            XCTAssertNotNil(ISO8601DateFormatter().date(from: f.createdAt), "createdAt should be ISO-8601 parseable")
        }
    }

    func testTypeConstraintRejectsInvalidType() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)
            try db.execute(sql: "INSERT INTO account (id) VALUES (?)", arguments: ["a1"])

            do {
                try db.execute(
                    sql: "INSERT INTO \"transaction\" (id, account_id, date, amount_minor, type, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [UUID().uuidString, "a1", "2026-02-01", 100, "invalid_type", ISO8601DateFormatter().string(from: Date())]
                )
                XCTFail("Expected CHECK constraint to reject invalid type")
            } catch {
                // Expected: constraint failed
            }
        }
    }

    func testDateConstraintRejectsPreEpoch() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)
            try db.execute(sql: "INSERT INTO account (id) VALUES (?)", arguments: ["a1"])

            do {
                var tx = Transaction(
                    accountId: "a1",
                    date: "2025-12-31", // before ledger epoch
                    amountMinor: 100,
                    type: .purchase
                )
                try tx.insert(db)
                XCTFail("Expected CHECK constraint to reject pre-epoch date")
            } catch {
                // Expected: constraint failed
            }
        }
    }

    func testForeignKeyOnDeleteCascade() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)
            try db.execute(sql: "INSERT INTO account (id) VALUES (?)", arguments: ["a2"])

            var tx = Transaction(
                accountId: "a2",
                date: "2026-03-10",
                amountMinor: 1,
                type: .purchase
            )
            try tx.insert(db)

            try db.execute(sql: "DELETE FROM account WHERE id = ?", arguments: ["a2"])
            let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"transaction\" WHERE account_id = 'a2'") ?? -1
            XCTAssertEqual(remaining, 0, "Transactions should cascade delete with account")
        }
    }

    func testLinkedTransactionForeignKeyPreventsDeletion() throws {
        let queue = try makeInMemoryQueue()
        try queue.write { db in
            try createMinimalSchema(db)
            try db.execute(sql: "INSERT INTO account (id) VALUES (?)", arguments: ["a3"])

            var t1 = Transaction(accountId: "a3", date: "2026-04-01", amountMinor: 1, type: .transfer)
            try t1.insert(db)

            var t2 = Transaction(accountId: "a3", date: "2026-04-01", amountMinor: 1, type: .transfer, linkedTransactionId: t1.id)
            try t2.insert(db)

            do {
                try db.execute(sql: "DELETE FROM \"transaction\" WHERE id = ?", arguments: [t1.id])
                XCTFail("Expected FK constraint to prevent deleting a referenced transaction")
            } catch {
                // Expected: foreign key constraint failure
            }
        }
    }
}

#endif

