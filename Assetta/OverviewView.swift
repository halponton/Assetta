import SwiftUI

struct OverviewView: View {
    @State private var totalCash: Int64 = 0
    @State private var totalSavings: Int64 = 0
    @State private var incomePlanned: Int64 = 0
    @State private var incomeActual: Int64 = 0
    @State private var budgeted: Int64 = 0
    @State private var spent: Int64 = 0
    @State private var recoveryPressure: Int64 = 0
    @State private var unallocatedIncome: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            metricColumn(title: "Cash", value: totalCash)
                            metricColumn(title: "Savings", value: totalSavings)
                            metricColumn(title: "Net", value: totalCash + totalSavings)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Income & Budget")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Planned vs Actual")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                labelledValue(label: "Planned", value: incomePlanned)
                                labelledValue(label: "Actual", value: incomeActual)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Budget")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                labelledValue(label: "Budgeted", value: budgeted)
                                labelledValue(label: "Spent", value: spent)
                                labelledValue(label: "Unallocated", value: unallocatedIncome)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recovery")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if recoveryPressure > 0 {
                            Text("Monthly adjustment \(formatMinorToCurrency(recoveryPressure))")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            Text("No active recovery pressure")
                                .foregroundStyle(.secondary)
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

    private func metricColumn(title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formatMinorToCurrency(value))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelledValue(label: String, value: Int64) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatMinorToCurrency(value))
                .monospacedDigit()
        }
        .font(.body)
    }

    private func currentMonthString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    @MainActor
    private func reload() async {
        do {
            let month = currentMonthString()
            totalCash = try Persistence.computeTotalCashBalance()
            totalSavings = try Persistence.computeTotalSavingsBalanceForWorkspace()
            let income = try Persistence.computeIncomeVariance(forMonth: month)
            incomePlanned = income.planned
            incomeActual = income.actual

            let overspend = try Persistence.computeMonthlyOverspend(forMonth: month)
            budgeted = overspend.totalBudgeted
            spent = overspend.totalActual

            recoveryPressure = try Persistence.computeRecoveryAdjustments(forMonth: month)

            let summary = try Persistence.computeBudgetSummary(forMonth: month)
            unallocatedIncome = summary.unallocated

            errorMessage = nil
        } catch {
            errorMessage = "Unable to load overview: \(error.localizedDescription)"
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
}

