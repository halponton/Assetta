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
