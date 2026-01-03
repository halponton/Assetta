//
//  ContentView.swift
//  Assetta
//
//  Created by Hal Ponton on 31/12/2025.
//

import SwiftUI

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview
        case accounts
        case budget
        case savings
        case recovery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .accounts: return "Accounts"
            case .budget: return "Budget"
            case .savings: return "Savings"
            case .recovery: return "Recovery"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: return "rectangle.grid.1x2"
            case .accounts: return "creditcard"
            case .budget: return "chart.pie"
            case .savings: return "lock.rectangle"
            case .recovery: return "arrow.uturn.backward"
            }
        }
    }

    @State private var selection: Section = .overview

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Assetta")
        } detail: {
            detailView(for: selection)
        }
        #else
        TabView(selection: $selection) {
            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: Section.overview.systemImage) }
                .tag(Section.overview)

            NavigationStack { AccountsView() }
                .tabItem { Label("Accounts", systemImage: Section.accounts.systemImage) }
                .tag(Section.accounts)

            NavigationStack { BudgetOverviewView() }
                .tabItem { Label("Budget", systemImage: Section.budget.systemImage) }
                .tag(Section.budget)

            NavigationStack { SavingsOverviewView() }
                .tabItem { Label("Savings", systemImage: Section.savings.systemImage) }
                .tag(Section.savings)

            NavigationStack { RecoveryOverviewView() }
                .tabItem { Label("Recovery", systemImage: Section.recovery.systemImage) }
                .tag(Section.recovery)
        }
        #endif
    }

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .overview:
            NavigationStack { OverviewView() }
        case .accounts:
            NavigationStack { AccountsView() }
        case .budget:
            NavigationStack { BudgetOverviewView() }
        case .savings:
            NavigationStack { SavingsOverviewView() }
        case .recovery:
            NavigationStack { RecoveryOverviewView() }
        }
    }
}

#Preview {
    ContentView()
}
