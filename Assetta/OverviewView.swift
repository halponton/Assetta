import SwiftUI

struct OverviewView: View {
    @State private var totalCashBalance: Int64 = 0
    @State private var totalSavingsBalance: Int64 = 0
    @State private var plannedIncome: Int64 = 0
    @State private var actualIncome: Int64 = 0
    @State private var incomeVariance: Int64 = 0
    @State private var budgetedTotal: Int64 = 0
    @State private var actualSpend: Int64 = 0
    @State private var recoveryPressure: Int64 = 0
    @State private var unallocatedDiscretionary: Int64 = 0
    @State private var discretionaryCapacity: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview")
                        .font(.largeTitle.bold())
                    Text(monthLabel())
                        .foregroundStyle(.secondary)
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Position")
                            .font(.headline)
                        HStack(spacing: 16) {
                            balancePill(title: "Total Cash", value: totalCashBalance)
                            balancePill(title: "Savings", value: totalSavingsBalance)
                            balancePill(title: "Net Position", value: totalCashBalance + totalSavingsBalance)
                        }
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Income")
                                .font(.headline)
                            Spacer()
                            Text("Planned vs actual")
                                .foregroundStyle(.secondary)
                        }
                        gridRow(label: "Planned", value: plannedIncome)
                        gridRow(label: "Actual", value: actualIncome)
                        gridRow(label: "Variance", value: incomeVariance, emphasizeNegative: true)
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Budget")
                                .font(.headline)
                            Spacer()
                            Text("This month")
                                .foregroundStyle(.secondary)
                        }
                        gridRow(label: "Budgeted", value: budgetedTotal)
                        gridRow(label: "Spent", value: actualSpend)
                        gridRow(label: "Unallocated", value: unallocatedDiscretionary)
                        gridRow(label: "Recovery pressure", value: recoveryPressure, emphasizeNegative: true)
                        gridRow(label: "Discretionary capacity", value: discretionaryCapacity)
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unallocated income")
                            .font(.headline)
                        Text("Left intentionally untouched until you direct it. Touch to plan where it goes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formatMinorToCurrency(unallocatedDiscretionary))
                            .font(.title2.monospacedDigit())
                        NavigationLink(destination: BudgetPlannerView()) {
                            Label("Open Budget Planner", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(Color.clear)
        .onAppear { loadSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in loadSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CategoriesDidChange"))) { _ in loadSnapshot() }
    }

    private func loadSnapshot() {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.year, .month], from: Date())
        guard let year = comps.year, let month = comps.month else { return }
        let monthString = String(format: "%04d-%02d", year, month)
        do {
            totalSavingsBalance = try Persistence.computeTotalSavingsBalanceForWorkspace()
            totalCashBalance = try Persistence.computeTotalCashBalanceForWorkspace()
            let income = try Persistence.computeIncomeVariance(forMonth: monthString)
            plannedIncome = income.planned
            actualIncome = income.actual
            incomeVariance = income.variance

            let monthly = try Persistence.computeMonthlyOverspend(forMonth: monthString)
            budgetedTotal = monthly.totalBudgeted
            actualSpend = monthly.totalActual
            recoveryPressure = try Persistence.computeRecoveryAdjustments(forMonth: monthString)
            let summary = try Persistence.computeBudgetAndObligationSummary(forMonth: monthString)
            unallocatedDiscretionary = summary.unallocatedDiscretionary
            discretionaryCapacity = summary.discretionaryCapacity
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func monthLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date())
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
    private func gridRow(label: String, value: Int64, emphasizeNegative: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(formatMinorToCurrency(value))
                .monospacedDigit()
                .foregroundStyle(emphasizeNegative && value < 0 ? .pink : .primary)
        }
    }

    @ViewBuilder
    private func balancePill(title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formatMinorToCurrency(value))
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

