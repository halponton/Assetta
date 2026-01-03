import SwiftUI

struct SavingsOverviewView: View {
    @State private var savingsAccounts: [Account] = []
    @State private var balances: [String: Int64] = [:]
    @State private var recentMovements: [Transaction] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Savings")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accounts")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if savingsAccounts.isEmpty {
                            Text("No savings accounts yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(savingsAccounts, id: \.id) { account in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name)
                                                .font(.headline)
                                            if let institution = account.institution, !institution.isEmpty {
                                                Text(institution)
                                                    .foregroundStyle(.secondary)
                                                    .font(.footnote)
                                            }
                                        }
                                        Spacer()
                                        Text(formatMinorToCurrency(balances[account.id] ?? 0))
                                            .monospacedDigit()
                                            .font(.title3.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent movements")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if recentMovements.isEmpty {
                            Text("No contributions or withdrawals yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(recentMovements, id: \.id) { tx in
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let date = isoDate(from: tx.date) {
                                                Text(date, style: .date)
                                            } else {
                                                Text(tx.date)
                                            }
                                            Text(label(for: tx.type))
                                                .foregroundStyle(.secondary)
                                                .font(.footnote)
                                        }
                                        Spacer()
                                        Text(formatMinorToCurrency(tx.amountMinor))
                                            .monospacedDigit()
                                            .font(.body.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .background(.regularMaterial)
        .task { await reload() }
        .refreshable { await reload() }
    }

    @MainActor
    private func reload() async {
        do {
            let accounts = try Persistence.listSavingsAccounts()
            var balanceMap: [String: Int64] = [:]
            for account in accounts {
                balanceMap[account.id] = try Persistence.computeSavingsBalance(accountId: account.id)
            }
            savingsAccounts = accounts
            balances = balanceMap

            // Recent movements across all savings accounts
            let workspaceMovements = try fetchRecentSavingsMovements()
            recentMovements = Array(workspaceMovements.prefix(8))
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load savings: \(error.localizedDescription)"
        }
    }

    private func fetchRecentSavingsMovements() throws -> [Transaction] {
        guard let dbQueue = Persistence.dbQueue else { throw PersistenceError.databaseUnavailable }
        let workspaceId = try Persistence.currentWorkspaceId()
        return try dbQueue.read { db in
            try Transaction.fetchAll(db, sql: """
                SELECT t.*
                FROM "transaction" t
                JOIN account a ON a.id = t.account_id
                WHERE a.workspace_id = ?
                  AND a.type = 'savings'
                  AND t.type IN ('savings_contribution', 'savings_withdrawal')
                ORDER BY t.date DESC, t.created_at DESC
            """, arguments: [workspaceId])
        }
    }

    private func formatMinorToCurrency(_ minor: Int64) -> String {
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
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private func label(for type: Transaction.TransactionType) -> String {
        switch type {
        case .savings_contribution:
            return "Contribution"
        case .savings_withdrawal:
            return "Withdrawal"
        default:
            return type.rawValue
        }
    }
}

