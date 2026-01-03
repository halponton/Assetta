//
//  ContentView.swift
//  Assetta
//
//  Created by Hal Ponton on 31/12/2025.
//

import SwiftUI

private enum PrimarySection: String, CaseIterable, Identifiable {
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

    var icon: String {
        switch self {
        case .overview: return "circle.grid.2x2"
        case .accounts: return "creditcard"
        case .budget: return "list.bullet.rectangle"
        case .savings: return "shield.lefthalf.filled"
        case .recovery: return "arrow.uturn.backward.circle"
        }
    }
}

struct ContentView: View {
    @State private var selection: PrimarySection = .overview

    var body: some View {
        Group {
#if os(macOS)
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(PrimarySection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Assetta")
            } detail: {
                NavigationStack {
                    sectionView(for: selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(.thinMaterial)
            }
#else
            TabView(selection: $selection) {
                NavigationStack { sectionView(for: .overview) }
                    .tabItem { Label("Overview", systemImage: PrimarySection.overview.icon) }
                    .tag(PrimarySection.overview)

                NavigationStack { AccountsView() }
                    .tabItem { Label("Accounts", systemImage: PrimarySection.accounts.icon) }
                    .tag(PrimarySection.accounts)

                NavigationStack { BudgetOverviewView() }
                    .tabItem { Label("Budget", systemImage: PrimarySection.budget.icon) }
                    .tag(PrimarySection.budget)

                NavigationStack { SavingsHomeView() }
                    .tabItem { Label("Savings", systemImage: PrimarySection.savings.icon) }
                    .tag(PrimarySection.savings)

                NavigationStack { RecoveryHomeView() }
                    .tabItem { Label("Recovery", systemImage: PrimarySection.recovery.icon) }
                    .tag(PrimarySection.recovery)
            }
#endif
        }
    }

    @ViewBuilder
    private func sectionView(for section: PrimarySection) -> some View {
        switch section {
        case .overview:
            OverviewView()
        case .accounts:
            AccountsView()
        case .budget:
            BudgetOverviewView()
        case .savings:
            SavingsHomeView()
        case .recovery:
            RecoveryHomeView()
        }
    }
}

#Preview {
    ContentView()
}
