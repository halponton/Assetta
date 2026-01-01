//
//  DatabaseManager.swift
//  Assetta
//
//  Created by Xcode Assistant on 01/01/2026.
//

import Foundation
import GRDB

/// Centralized database bootstrap and access point.
/// Uses GRDB's DatabaseQueue for simplicity.
final class DatabaseManager {
    static let shared = DatabaseManager()
    private init() {}

    /// The shared database queue once set up.
    private(set) var dbQueue: DatabaseQueue?

    /// Initializes the database if it hasn't been set up yet and runs migrations.
    /// Safe to call multiple times; subsequent calls are no-ops.
    func setUpDatabase() throws {
        if dbQueue != nil { return }

        let dbURL = try Self.databaseURL()
        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let queue = try DatabaseQueue(path: dbURL.path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            // Minimal schema to let the app bootstrap a workspace
            try db.create(table: "workspace") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("type", .text).notNull().defaults(to: "personal")
            }
        }
        migrator.registerMigration("v2_accounts") { db in
            try db.create(table: "account") { t in
                // Primary key: UUID stored as TEXT
                t.column("id", .text).notNull()
                // Foreign key to workspace(id)
                t.column("workspace_id", .integer).notNull()
                // Basic fields
                t.column("name", .text).notNull().collate(.nocase) // case-insensitive uniqueness via NOCASE
                t.column("type", .text).notNull()
                t.column("institution", .text) // nullable
                t.column("created_at", .text).notNull()

                // Constraints
                t.primaryKey(["id"]) // TEXT PK (UUID)
                t.foreignKey(["workspace_id"], references: "workspace", columns: ["id"], onDelete: .cascade)
                t.check(sql: "type IN ('current','credit','savings','investment')")
                t.uniqueKey(["workspace_id", "name"]) // data-quality guard: unique account name per workspace
            }
            try db.create(index: "idx_account_workspace_id", on: "account", columns: ["workspace_id"])
        }
        migrator.registerMigration("v3_transactions") { db in
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

                // Optional notes
                t.column("notes", .text)

                // Creation timestamp (ISO-8601 string)
                t.column("created_at", .text).notNull()
            }
            // Index to speed up account/date queries
            try db.create(index: "transaction_account_date_idx", on: "transaction", columns: ["account_id", "date"])
        }
        try migrator.migrate(queue)

        dbQueue = queue
    }

    // MARK: - Helpers

    /// Location of the SQLite database file inside Application Support.
    private static func databaseURL() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirURL = baseURL.appendingPathComponent("Assetta", isDirectory: true)
        // Create directory if missing and exclude from backups
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirURL = dirURL
        try? mutableDirURL.setResourceValues(resourceValues)
        return dirURL.appendingPathComponent("Assetta.sqlite")
    }
}

