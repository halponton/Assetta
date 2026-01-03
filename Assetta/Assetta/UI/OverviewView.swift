import SwiftUI

struct OverviewView: View {
    @Binding var selectedSection: MainSection

    @State private var snapshot = OverviewSnapshot()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(snapshot.monthLabel) Snapshot")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Net position")
                                .font(.headline)
                            Text(formatCurrency(snapshot.netPosition))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            HStack(spacing: 12) {
                                CapsuleStat(label: "Cash", value: formatCurrency(snapshot.cashTotal))
                                CapsuleStat(label: "Savings", value: formatCurrency(snapshot.savingsTotal))
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Income this month")
                                    .font(.headline)
                                Spacer()
                                Button("View budget") { jump(to: .budget) }
                                    .buttonStyle(.bordered)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                SummaryRow(title: "Planned", value: formatCurrency(snapshot.plannedIncome))
                                SummaryRow(title: "Actual", value: formatCurrency(snapshot.actualIncome))
                                SummaryRow(title: "Variance", value: formatCurrency(snapshot.incomeVariance), emphasis: snapshot.incomeVariance != 0)
                                Divider()
                                SummaryRow(title: "Unallocated income", value: formatCurrency(snapshot.unallocatedIncome))
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Budget status")
                                    .font(.headline)
                                Spacer()
                                Button("Adjust plan") { jump(to: .budget) }
                                    .buttonStyle(.bordered)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                SummaryRow(title: "Budgeted", value: formatCurrency(snapshot.totalBudgeted))
                                SummaryRow(title: "Spent", value: formatCurrency(snapshot.totalActualSpend))
                                SummaryRow(title: "Remaining", value: formatCurrency(snapshot.totalBudgeted - snapshot.totalActualSpend))
                                if snapshot.overspend > 0 {
                                    SummaryRow(title: "Overspend", value: formatCurrency(snapshot.overspend), emphasis: true)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recovery pressure")
                                    .font(.headline)
                                Spacer()
                                Button("Schedules") { jump(to: .recovery) }
                                    .buttonStyle(.bordered)
                            }
                            if snapshot.recoveryAdjustment > 0 {
                                Text("\(formatCurrency(snapshot.recoveryAdjustment)) applied this month")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                            } else {
                                Text("No active recovery this month")
                                    .foregroundStyle(.secondary)
                            }
                            if snapshot.activeRecoveries > 0 {
                                Text("\(snapshot.activeRecoveries) schedule\(snapshot.activeRecoveries == 1 ? "" : "s") in progress")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(.clear)
            .task { await refresh() }
            .refreshable { await refresh() }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .navigationTitle("Overview")
        }
    }

    private func jump(to section: MainSection) {
        withAnimation {
            selectedSection = section
        }
    }

    private func refresh() async {
        do {
            let month = currentMonth()
            let accounts = try Persistence.listAccounts()
            let balances = try Persistence.computeAccountBalancesById()
            let cash = accounts
                .filter { $0.type == .current || $0.type == .credit }
                .map { balances[$0.id] ?? 0 }
                .reduce(0, +)
            let savings = try Persistence.computeTotalSavingsBalanceForWorkspace()
            let income = try Persistence.computeIncomeVariance(forMonth: month)
            let budgetSummary = try Persistence.computeBudgetSummary(forMonth: month)
            let spend = try Persistence.computeMonthlyOverspend(forMonth: month)
            let recovery = try Persistence.computeRecoveryAdjustments(forMonth: month)
            let activeRecoveries = try Persistence.listActiveRecoverySchedules().count
            let positiveVariance = max(income.variance, 0)
            let unallocatedIncome = budgetSummary.unallocated + positiveVariance

            await MainActor.run {
                snapshot = OverviewSnapshot(
                    monthLabel: formattedMonthLabel(for: month),
                    cashTotal: cash,
                    savingsTotal: savings,
                    plannedIncome: income.planned,
                    actualIncome: income.actual,
                    totalBudgeted: spend.totalBudgeted,
                    totalActualSpend: spend.totalActual,
                    recoveryAdjustment: recovery,
                    activeRecoveries: activeRecoveries,
                    unallocatedIncome: unallocatedIncome
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
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

    private func currentMonth() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func formattedMonthLabel(for month: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: month) {
            let output = DateFormatter()
            output.dateFormat = "LLLL yyyy"
            return output.string(from: date)
        }
        return month
    }
}

private struct OverviewSnapshot {
    var monthLabel: String = ""
    var cashTotal: Int64 = 0
    var savingsTotal: Int64 = 0
    var plannedIncome: Int64 = 0
    var actualIncome: Int64 = 0
    var totalBudgeted: Int64 = 0
    var totalActualSpend: Int64 = 0
    var recoveryAdjustment: Int64 = 0
    var activeRecoveries: Int = 0
    var unallocatedIncome: Int64 = 0

    var netPosition: Int64 { cashTotal + savingsTotal }
    var incomeVariance: Int64 { actualIncome - plannedIncome }
    var overspend: Int64 { max(0, totalActualSpend - totalBudgeted) }
}

private struct CapsuleStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }
}
