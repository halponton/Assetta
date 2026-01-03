//
//  ContentView.swift
//  Assetta
//
//  Created by Hal Ponton on 31/12/2025.
//

import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case overview
    case accounts
    case budget
    case savings
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .accounts: "Accounts"
        case .budget: "Budget"
        case .savings: "Savings"
        case .recovery: "Recovery"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .accounts: "creditcard"
        case .budget: "chart.bar.doc.horizontal"
        case .savings: "vault"
        case .recovery: "arrow.triangle.2.circlepath"
        }
    }
}

struct ContentView: View {
    @State private var selection: MainSection = .overview

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(MainSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Assetta")
        } detail: {
            detailView(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.thinMaterial)
        }
        .navigationSplitViewStyle(.balanced)
        #else
        TabView(selection: $selection) {
            overviewView
                .tabItem { Label(MainSection.overview.title, systemImage: MainSection.overview.systemImage) }
                .tag(MainSection.overview)

            AccountsView()
                .tabItem { Label(MainSection.accounts.title, systemImage: MainSection.accounts.systemImage) }
                .tag(MainSection.accounts)

            budgetView
                .tabItem { Label(MainSection.budget.title, systemImage: MainSection.budget.systemImage) }
                .tag(MainSection.budget)

            savingsView
                .tabItem { Label(MainSection.savings.title, systemImage: MainSection.savings.systemImage) }
                .tag(MainSection.savings)

            recoveryView
                .tabItem { Label(MainSection.recovery.title, systemImage: MainSection.recovery.systemImage) }
                .tag(MainSection.recovery)
        }
        #endif
    }

    @ViewBuilder
    private var overviewView: some View {
        OverviewView(selectedSection: $selection)
            .navigationTitle(MainSection.overview.title)
    }

    @ViewBuilder
    private var budgetView: some View {
        BudgetHomeView()
            .navigationTitle(MainSection.budget.title)
    }

    @ViewBuilder
    private var savingsView: some View {
        SavingsHomeView()
            .navigationTitle(MainSection.savings.title)
    }

    @ViewBuilder
    private var recoveryView: some View {
        RecoveryHomeView()
            .navigationTitle(MainSection.recovery.title)
    }

    @ViewBuilder
    private func detailView(for section: MainSection) -> some View {
        switch section {
        case .overview:
            overviewView
                .padding()
        case .accounts:
            AccountsView()
        case .budget:
            budgetView
                .padding()
        case .savings:
            savingsView
                .padding()
        case .recovery:
            recoveryView
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
