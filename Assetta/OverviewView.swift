import SwiftUI

struct OverviewSnapshot {
    let totalCash: Int64
    let totalSavings: Int64
    let netPosition: Int64
    let plannedIncome: Int64
    let actualIncome: Int64
    let budgeted: Int64
    let spent: Int64
    let recoveryPressure: Int64
    let unallocatedIncome: Int64
    let monthLabel: String

    static func loadCurrent() throws -> OverviewSnapshot {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: Date())

        let totalSavings = try Persistence.computeTotalSavingsBalanceForWorkspace()
        let totalCash = try Persistence.computeTotalCashBalanceForWorkspace()
        let net = totalCash + totalSavings

        let income = try Persistence.computeIncomeVariance(forMonth: month)
        let budgeted = try Persistence.computeTotalBudgetedAllCategories(forMonth: month)
        let spent = try Persistence.computeTotalActualSpend(forMonth: month)
        let recovery = try Persistence.computeRecoveryAdjustments(forMonth: month)
        let budgetSummary = try Persistence.computeBudgetAndObligationSummary(forMonth: month)

        return OverviewSnapshot(
            totalCash: totalCash,
            totalSavings: totalSavings,
            netPosition: net,
            plannedIncome: income.planned,
            actualIncome: income.actual,
            budgeted: budgeted,
            spent: spent,
            recoveryPressure: recovery,
            unallocatedIncome: budgetSummary.unallocatedDiscretionary,
            monthLabel: month
        )
    }
}

struct OverviewView: View {
    @State private var snapshot: OverviewSnapshot?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mission Control")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                if let snap = snapshot {
                    VStack(spacing: 16) {
                        GlassCard(title: "Position") {
                            VStack(alignment: .leading, spacing: 12) {
                                balanceRow(label: "Cash", value: snap.totalCash)
                                balanceRow(label: "Savings", value: snap.totalSavings)
                                Divider().opacity(0.15)
                                balanceRow(label: "Net", value: snap.netPosition, weight: .semibold)
                            }
                        }

                        GlassCard(title: "This month (\(snap.monthLabel))") {
                            VStack(alignment: .leading, spacing: 12) {
                                metricRow(title: "Income", primary: formatMinorCurrency(snap.actualIncome), detail: "Planned " + formatMinorCurrency(snap.plannedIncome))
                                metricRow(title: "Budget vs spend", primary: formatMinorCurrency(snap.budgeted), detail: "Spent " + formatMinorCurrency(snap.spent))
                                if snap.recoveryPressure > 0 {
                                    metricRow(title: "Recovery applied", primary: formatMinorCurrency(snap.recoveryPressure), detail: "Pressure on capacity")
                                }
                            }
                        }

                        GlassCard(title: "Unallocated") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Income not yet given a job")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(formatMinorCurrency(snapshot?.unallocatedIncome ?? 0))
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                } else {
                    ProgressView("Loading")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(.regularMaterial)
        .navigationTitle("Overview")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { reloadButton } }
        .task { reload() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }) {
            if let message = errorMessage { Text(message) }
        }
    }

    private var reloadButton: some View {
        Button {
            reload()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Reload snapshot")
    }

    private func reload() {
        do {
            snapshot = try OverviewSnapshot.loadCurrent()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func balanceRow(label: String, value: Int64, weight: Font.Weight = .regular) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatMinorCurrency(value))
                .font(.system(.title3, design: .rounded).weight(weight))
                .monospacedDigit()
        }
    }

    private func metricRow(title: String, primary: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(primary)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OverviewView()
}
