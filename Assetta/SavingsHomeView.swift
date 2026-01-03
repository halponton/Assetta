import SwiftUI

struct SavingsHomeView: View {
    @State private var savingsAccounts: [Account] = []
    @State private var balances: [String: Int64] = [:]
    @State private var movements: [Transaction] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Savings")
                        .font(.largeTitle.bold())
                    Text("Destination-first, calm balances")
                        .foregroundStyle(.secondary)
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accounts")
                            .font(.headline)
                        if savingsAccounts.isEmpty {
                            Text("No savings accounts yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(savingsAccounts, id: \.id) { account in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name)
                                                .font(.headline)
                                            if let inst = account.institution, !inst.isEmpty {
                                                Text(inst)
                                                    .foregroundStyle(.secondary)
                                                    .font(.subheadline)
                                            }
                                        }
                                        Spacer()
                                        Text(formatMinorToCurrency(balances[account.id] ?? 0))
                                            .font(.title3.monospacedDigit())
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent movements")
                            .font(.headline)
                        if movements.isEmpty {
                            Text("No savings movements yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(movements, id: \.id) { tx in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(title(for: tx))
                                                .font(.headline)
                                            if let date = isoDate(from: tx.date) {
                                                Text(date, style: .date)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let notes = tx.notes, !notes.isEmpty {
                                                Text(notes)
                                                    .foregroundStyle(.secondary)
                                                    .font(.footnote)
                                            }
                                        }
                                        Spacer()
                                        Text(formatMinorToCurrency(tx.amountMinor))
                                            .font(.title3.monospacedDigit())
                                            .foregroundStyle(tx.type == .savings_withdrawal ? .pink : .primary)
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CategoriesDidChange"))) { _ in load() }
    }

    private func load() {
        do {
            savingsAccounts = try Persistence.listSavingsAccounts()
            var bal: [String: Int64] = [:]
            for acc in savingsAccounts {
                bal[acc.id] = try Persistence.computeSavingsBalance(accountId: acc.id)
            }
            balances = bal
            movements = try Persistence.listRecentSavingsMovements(limit: 8)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func title(for tx: Transaction) -> String {
        switch tx.type {
        case .savings_contribution: return "Contribution"
        case .savings_withdrawal: return "Withdrawal"
        default: return tx.type.rawValue
        }
    }

    private func isoDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
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

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

