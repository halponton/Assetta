//
//  OnboardingBootstrap.swift
//  Assetta
//
//  Created by Xcode Assistant on 01/01/2026.
//

import Foundation
import GRDB

/// Ensures the app has the minimum required data to run after first launch.
struct OnboardingBootstrap {
    /// Creates an initial personal workspace if none exists.
    func ensureInitialWorkspace() throws {
        guard let dbQueue = DatabaseManager.shared.dbQueue else {
            throw NSError(domain: "Assetta", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not initialized"])
        }

        try dbQueue.write { db in
            // Check if a workspace already exists
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workspace") ?? 0
            if count == 0 {
                try db.execute(sql: "INSERT INTO workspace (name, type) VALUES (?, ?)", arguments: ["Personal", "personal"])
            }
        }
    }
}
