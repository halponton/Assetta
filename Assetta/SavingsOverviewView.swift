import SwiftUI

struct SavingsMovementSnapshot: Identifiable, Hashable {
    let id = UUID()
    let accountName: String
    let date: String
    let amount: Int64
    let isContribution: Bool
    let notes: String?
}

struct SavingsAccountSnapshot: Identifiable, Hashable {
    let id: String
    let name: String
    let institution: String?
    let balance: Int64
}

struct SavingsOverviewView: View {
    @State private var accounts: [SavingsAccountSnapshot] = []
    @State private var movements: [SavingsMovementSnapshot] = []
    @State private var errorMessage: String?
    @State private var categories: [Category] = []
    @State private var showingMovement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Savings")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                GlassCard(title: "Balances") {
                    if accounts.isEmpty {
                        Text("No savings accounts yet")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(accounts) { account in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name)
                                        if let institution = account.institution, !institution.isEmpty {
                                            Text(institution)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(formatMinorCurrency(account.balance))
                                        .font(.title3.weight(.semibold))
                                        .monospacedDigit()
                                }
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }

                GlassCard(title: "Recent movements") {
                    if movements.isEmpty {
                        Text("No savings movements yet")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(movements.prefix(10)) { move in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(move.accountName)
                                        Text(move.date)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatMinorCurrency(move.amount))
                                        .foregroundStyle(move.isContribution ? .primary : .pink)
                                        .monospacedDigit()
                                }
                                if let notes = move.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(.regularMaterial)
        .navigationTitle("Savings")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Move Money") { showingMovement = true }
                Button(action: reload) { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showingMovement) {
            SavingsMovementView(categories: categories) { didCreate in
                if didCreate { reload() }
                showingMovement = false
            }
            #if os(macOS)
            .frame(minWidth: 520)
            #endif
        }
        .task { reload() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }) {
            if let message = errorMessage { Text(message) }
        }
    }

    private func reload() {
        do {
            let savingsAccounts = try Persistence.listSavingsAccounts()
            categories = try Persistence.listCategories()
            accounts = try savingsAccounts.map { account in
                let balance = try Persistence.computeSavingsBalance(accountId: account.id)
                return SavingsAccountSnapshot(id: account.id, name: account.name, institution: account.institution, balance: balance)
            }

            var movementRows: [SavingsMovementSnapshot] = []
            for account in savingsAccounts {
                let txs = try Persistence.listTransactions(accountId: account.id)
                for tx in txs where tx.type == .savings_contribution || tx.type == .savings_withdrawal {
                    let isContribution = tx.type == .savings_contribution
                    movementRows.append(SavingsMovementSnapshot(accountName: account.name, date: tx.date, amount: tx.amountMinor, isContribution: isContribution, notes: tx.notes))
                }
            }
            movements = movementRows.sorted { $0.date > $1.date }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

#Preview {
    SavingsOverviewView()
}
