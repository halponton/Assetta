//
//  ContentView.swift
//  Assetta
//
//  Created by Hal Ponton on 31/12/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedSection: AppSection = .overview

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Assetta")
            .listStyle(.sidebar)
        } detail: {
            sectionView(for: selectedSection)
        }
        #else
        TabView(selection: $selectedSection) {
            ForEach(AppSection.allCases, id: \.self) { section in
                NavigationStack {
                    sectionView(for: section)
                }
                .tabItem {
                    Label(section.title, systemImage: section.icon)
                }
                .tag(section)
            }
        }
        #endif
    }

    @ViewBuilder
    private func sectionView(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView()
        case .accounts:
            AccountsView()
        case .budget:
            BudgetOverviewView()
        case .savings:
            SavingsOverviewView()
        case .recovery:
            RecoveryOverviewView()
        }
    }
}

enum AppSection: CaseIterable, Hashable {
    case overview, accounts, budget, savings, recovery

    var title: String {
        switch self {
        case .overview: "Overview"
        case .accounts: "Accounts"
        case .budget: "Budget"
        case .savings: "Savings"
        case .recovery: "Recovery"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.3.offgrid"
        case .accounts: "creditcard"
        case .budget: "chart.pie"
        case .savings: "shield.lefthalf.filled"
        case .recovery: "arrow.triangle.2.circlepath"
        }
    }
}

#Preview {
    ContentView()
}
