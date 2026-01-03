import SwiftUI

struct SavingsHomeView: View {
    @State private var accounts: [Account] = []
    @State private var balances: [String: Int64] = [:]
    @State private var movements: [Transaction] = []
    @State private var categories: [Category] = []
    @State private var showingMovement = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Savings")
                                    .font(.headline)
                                Spacer()
                                Button("New movement") { showingMovement = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            SummaryRow(title: "Total savings", value: formatCurrency(totalSavings))
                            SummaryRow(title: "Accounts", value: "\(accounts.count)")
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Accounts")
                                .font(.headline)
                            if accounts.isEmpty {
                                Text("No savings accounts yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(accounts, id: \.id) { account in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(account.name)
                                                    .font(.subheadline.weight(.semibold))
                                                if let inst = account.institution, !inst.isEmpty {
                                                    Text(inst)
                                                        .foregroundStyle(.secondary)
                                                        .font(.footnote)
                                                }
                                            }
                                            Spacer()
                                            Text(formatCurrency(balances[account.id] ?? 0))
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent movements")
                                .font(.headline)
                            if movements.isEmpty {
                                Text("No savings movements yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(movements, id: \.id) { tx in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(movementTitle(for: tx))
                                                Spacer()
                                                Text(formatCurrency(tx.amountMinor))
                                                    .monospacedDigit()
                                                    .foregroundStyle(tx.amountMinor < 0 ? .pink : .primary)
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            if let date = isoDate(from: tx.date) {
                                                Text(date, style: .date)
                                                    .foregroundStyle(.secondary)
                                                    .font(.footnote)
                                            }
                                            if let notes = tx.notes, !notes.isEmpty {
                                                Text(notes)
                                                    .foregroundStyle(.secondary)
                                                    .font(.footnote)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingMovement) {
                SavingsMovementView(categories: categories) { didCreate in
                    if didCreate {
                        Task { await load() }
                    }
                    showingMovement = false
                }
                .frame(minWidth: 420)
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .navigationTitle("Savings")
        }
    }

    private var totalSavings: Int64 {
        balances.values.reduce(0, +)
    }

    private func load() async {
        do {
            let list = try Persistence.listSavingsAccounts()
            var balanceMap: [String: Int64] = [:]
            for account in list {
                balanceMap[account.id] = try Persistence.computeSavingsBalance(accountId: account.id)
            }
            let recentMovements = try Persistence.listRecentSavingsMovements(limit: 8)
            let cats = try Persistence.listCategories()

            await MainActor.run {
                accounts = list
                balances = balanceMap
                movements = recentMovements
                categories = cats
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func movementTitle(for tx: Transaction) -> String {
        switch tx.type {
        case .savings_contribution:
            return "Contribution"
        case .savings_withdrawal:
            return "Withdrawal"
        default:
            return tx.type.rawValue
        }
    }

    private func formatCurrency(_ minor: Int64) -> String {
        let number = NSDecimalNumber(value: minor).dividing(by: 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private func isoDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
