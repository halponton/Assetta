//
//  AssettaApp.swift
//  Assetta
//
//  Created by Hal Ponton on 31/12/2025.
//

import SwiftUI
import GRDB

@main
struct AssettaApp: App {
    @State private var launchError: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    do {
                        if DatabaseManager.shared.dbQueue == nil {
                            try DatabaseManager.shared.setUpDatabase()
                            try OnboardingBootstrap().ensureInitialWorkspace()
#if DEBUG
                            // TODO: Remove debug database inspection before shipping a full build.
                            DatabaseDebugInspector.debugPrintDatabaseState()
#endif
                        }
                    } catch {
                        launchError = String(describing: error)
                        print("Launch error: \(error)")
                    }
                }
        }
    }
}

