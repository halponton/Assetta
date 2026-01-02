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

        let config = DatabaseManager.makeConfiguration()
        let queue = try DatabaseQueue(path: dbURL.path, configuration: config)

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
        migrator.registerMigration("v4_categories") { db in
            // 1) Create category table (workspace-scoped)
            try db.create(table: "category") { t in
                t.column("id", .text).notNull()
                t.primaryKey(["id"]) // TEXT PK (UUID)

                t.column("workspace_id", .integer).notNull()
                t.foreignKey(["workspace_id"], references: "workspace", columns: ["id"], onDelete: .cascade)

                t.column("name", .text).notNull().collate(.nocase)
                t.column("is_system", .integer).notNull().defaults(to: 0)
                t.column("is_discretionary", .integer).notNull().defaults(to: 1)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()

                t.uniqueKey(["workspace_id", "name"]) // unique category name per workspace
            }
            try db.create(index: "idx_category_workspace_sort", on: "category", columns: ["workspace_id", "sort_order"]) // listing aid

            // 2) Rebuild transaction table to add category_id FK
            // Create the new table with the desired schema. Use self-FK to the temporary table name to avoid FK issues during rename.
            try db.create(table: "transaction_new") { t in
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
                t.foreignKey(["linked_transaction_id"], references: "transaction", columns: ["id"]) // self-FK references final table name

                // Optional category reference
                t.column("category_id", .text)
                t.foreignKey(["category_id"], references: "category", columns: ["id"]) // no cascade delete

                // Optional notes
                t.column("notes", .text)

                // Creation timestamp (ISO-8601 string)
                t.column("created_at", .text).notNull()
            }

            // Copy existing rows, with NULL category_id
            try db.execute(sql: """
                INSERT INTO "transaction_new" (id, account_id, date, amount_minor, type, linked_transaction_id, category_id, notes, created_at)
                SELECT id, account_id, date, amount_minor, type, linked_transaction_id, NULL AS category_id, notes, created_at FROM "transaction"
            """)

            // Drop old index if it exists (will be dropped with the table, but do it explicitly for clarity)
            try? db.execute(sql: "DROP INDEX IF EXISTS transaction_account_date_idx")

            // Replace old table
            try db.drop(table: "transaction")
            try db.rename(table: "transaction_new", to: "transaction")

            // Recreate index to speed up account/date queries
            try db.create(index: "transaction_account_date_idx", on: "transaction", columns: ["account_id", "date"])
        }
        migrator.registerMigration("v5_fix_transaction_self_fk") { db in
            // Rebuild the transaction table to ensure the self-FK references the final table name
            try db.create(table: "transaction_fix") { t in
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
                // Self-FK must reference the final table name
                t.foreignKey(["linked_transaction_id"], references: "transaction", columns: ["id"]) 

                // Optional category reference
                t.column("category_id", .text)
                t.foreignKey(["category_id"], references: "category", columns: ["id"]) // no cascade delete

                // Optional notes
                t.column("notes", .text)

                // Creation timestamp (ISO-8601 string)
                t.column("created_at", .text).notNull()
            }

            // Copy existing rows
            try db.execute(sql: """
                INSERT INTO "transaction_fix" (id, account_id, date, amount_minor, type, linked_transaction_id, category_id, notes, created_at)
                SELECT id, account_id, date, amount_minor, type, linked_transaction_id, category_id, notes, created_at FROM "transaction"
            """)

            // Drop old index if it exists
            try? db.execute(sql: "DROP INDEX IF EXISTS transaction_account_date_idx")

            // Replace old table
            try db.drop(table: "transaction")
            try db.rename(table: "transaction_fix", to: "transaction")

            // Recreate index to speed up account/date queries
            try db.create(index: "transaction_account_date_idx", on: "transaction", columns: ["account_id", "date"])
        }
        migrator.registerMigration("v6_income_plan") { db in
            try db.create(table: "income_plan") { t in
                // Primary key: UUID stored as TEXT
                t.column("id", .text).notNull()
                t.primaryKey(["id"]) // TEXT PK (UUID)

                // Foreign key to workspace(id)
                t.column("workspace_id", .integer).notNull()
                t.foreignKey(["workspace_id"], references: "workspace", columns: ["id"], onDelete: .cascade)

                // Month in format YYYY-MM
                t.column("month", .text).notNull()
                // Planned amount in minor units (Int64)
                t.column("planned_amount_minor", .integer).notNull()

                // Creation timestamp (ISO-8601 string)
                t.column("created_at", .text).notNull()

                // Unique per workspace and month
                t.uniqueKey(["workspace_id", "month"])
            }
            try db.create(index: "idx_income_plan_workspace_month", on: "income_plan", columns: ["workspace_id", "month"]) // accelerator for lookups
        }
        migrator.registerMigration("v7_budget") { db in
            // BudgetMonth table
            try db.create(table: "budget_month") { t in
                t.column("id", .text).notNull()
                t.primaryKey(["id"]) // TEXT PK (UUID)

                t.column("workspace_id", .integer).notNull()
                t.foreignKey(["workspace_id"], references: "workspace", columns: ["id"], onDelete: .cascade)

                // Month in format YYYY-MM
                t.column("month", .text).notNull()

                // Creation timestamp (ISO-8601 string)
                t.column("created_at", .text).notNull()

                // Unique per workspace and month
                t.uniqueKey(["workspace_id", "month"])
            }
            try db.create(index: "idx_budget_month_workspace_month", on: "budget_month", columns: ["workspace_id", "month"]) // accelerator for lookups

            // BudgetCategoryPlan table
            try db.create(table: "budget_category_plan") { t in
                t.column("budget_month_id", .text).notNull()
                t.column("category_id", .text).notNull()
                t.column("amount_minor", .integer).notNull()

                // Composite primary key
                t.primaryKey(["budget_month_id", "category_id"])

                // FKs
                t.foreignKey(["budget_month_id"], references: "budget_month", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["category_id"], references: "category", columns: ["id"]) // no cascade delete
            }
            try db.create(index: "idx_budget_category_plan_month", on: "budget_category_plan", columns: ["budget_month_id"]) // join aid
        }
        migrator.registerMigration("v8_obligation_plan") { db in
            // Planned obligations for non-discretionary categories
            try db.create(table: "obligation_plan") { t in
                t.column("budget_month_id", .text).notNull()
                t.column("category_id", .text).notNull()
                t.column("amount_minor", .integer).notNull()

                t.primaryKey(["budget_month_id", "category_id"]) // composite PK
                t.foreignKey(["budget_month_id"], references: "budget_month", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["category_id"], references: "category", columns: ["id"]) // no cascade delete
            }
            try db.create(index: "idx_obligation_plan_month", on: "obligation_plan", columns: ["budget_month_id"]) // join aid
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

    /// Shared GRDB configuration used across the app (and tests) to ensure
    /// SQLite foreign key enforcement is enabled for every connection.
    static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            // Enforce referential integrity globally
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return config
    }
}

