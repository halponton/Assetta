//
//  DatabaseDebugInspector.swift
//  Assetta
//
//  Created by Xcode Assistant on 01/01/2026.
//

import Foundation
import GRDB
// TODO: Remove this temporary database inspection helper before pushing a full build (production).

#if DEBUG
/// Temporary, DEBUG-only helper to inspect the database state without modifying it.
/// This uses the existing DatabaseQueue (and thus works with SQLCipher) and prints
/// a list of tables and the applied GRDB migrations to the console.
enum DatabaseDebugInspector {
    static func debugPrintDatabaseState() {
        guard let dbQueue = DatabaseManager.shared.dbQueue else {
            print("[DEBUG][DB] Database not initialized")
            return
        }
        do {
            try dbQueue.read { db in
                print("\n===== [DEBUG][DB] BEGIN INSPECTION =====")

                // 1) List tables
                print("-- Tables --")
                let tableRows = try Row.fetchAll(
                    db,
                    sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                )
                if tableRows.isEmpty {
                    print("(no tables)")
                } else {
                    for row in tableRows {
                        let name: String = row["name"]
                        print("table: \(name)")
                    }
                }

                // 2) Migrations (identifier + appliedAt)
                print("-- GRDB Migrations --")
                let hasMigrationsTable = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='grdb_migrations')"
                ) ?? false
                if hasMigrationsTable {
                    let migRows = try Row.fetchAll(
                        db,
                        sql: "SELECT identifier, appliedAt FROM grdb_migrations ORDER BY appliedAt"
                    )
                    if migRows.isEmpty {
                        print("(grdb_migrations is empty)")
                    } else {
                        for row in migRows {
                            let identifier: String = row["identifier"]
                            let appliedAt: String = row["appliedAt"]
                            print("migration: \(identifier) at \(appliedAt)")
                        }
                    }
                } else {
                    print("(grdb_migrations table not found)")
                }

                print("===== [DEBUG][DB] END INSPECTION =====\n")
            }
        } catch {
            print("[DEBUG][DB] Inspection error: \(error)")
        }
    }
}
#endif

