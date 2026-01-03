import SwiftUI

struct BudgetCategorySnapshot: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let budgeted: Int64
    let actual: Int64
    let remaining: Int64
}

struct BudgetSummarySnapshot {
    let monthLabel: String
    let plannedIncome: Int64
    let plannedObligations: Int64
    let discretionaryBudgeted: Int64
    let discretionaryCapacity: Int64
    let unallocatedDiscretionary: Int64
    let totalActualSpend: Int64
    let totalBudgeted: Int64
    let recoveryApplied: Int64
}

struct BudgetOverviewView: View {
    @State private var summary: BudgetSummarySnapshot?
    @State private var categories: [BudgetCategorySnapshot] = []
    @State private var errorMessage: String?
    @State private var showingPlanner = false
    @State private var showingIncomePlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Budget")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                if let summary {
                    VStack(spacing: 16) {
                        GlassCard(title: "Current month (\(summary.monthLabel))") {
                            VStack(alignment: .leading, spacing: 12) {
                                metricRow(label: "Planned income", value: summary.plannedIncome)
                                metricRow(label: "Planned obligations", value: summary.plannedObligations)
                                if summary.recoveryApplied > 0 {
                                    metricRow(label: "Recovery applied", value: summary.recoveryApplied)
                                }
                                Divider().opacity(0.15)
                                metricRow(label: "Discretionary capacity", value: summary.discretionaryCapacity, weight: .semibold)
                                metricRow(label: "Budgeted", value: summary.discretionaryBudgeted)
                                metricRow(label: "Unallocated", value: summary.unallocatedDiscretionary, emphasis: true)
                            }
                        }

                        GlassCard(title: "Reality check") {
                            VStack(alignment: .leading, spacing: 8) {
                                metricRow(label: "Total budgeted", value: summary.totalBudgeted)
                                metricRow(label: "Actual spend", value: summary.totalActualSpend)
                                progressLine(budgeted: summary.totalBudgeted, actual: summary.totalActualSpend)
                            }
                        }

                        GlassCard(title: "Categories") {
                            VStack(alignment: .leading, spacing: 12) {
                                if categories.isEmpty {
                                    Text("No discretionary categories yet")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(categories) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(item.name)
                                                Spacer()
                                                Text(formatMinorCurrency(item.remaining))
                                                    .foregroundStyle(item.remaining >= 0 ? .secondary : .pink)
                                                    .monospacedDigit()
                                            }
                                            progressLine(budgeted: item.budgeted, actual: item.actual)
                                        }
                                        .padding(.vertical, 4)
                                        Divider().opacity(0.1)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Loading budget")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(.regularMaterial)
        .navigationTitle("Budget")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Income Plan") { showingIncomePlan = true }
                Button("Adjust Plan") { showingPlanner = true }
                Button(action: reload) { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showingPlanner) {
            BudgetPlannerView()
        }
        .sheet(isPresented: $showingIncomePlan) {
            IncomePlanView()
        }
        .task { reload() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }) {
            if let message = errorMessage { Text(message) }
        }
    }

    private func reload() {
        do {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM"
            let month = formatter.string(from: Date())
            let income = try Persistence.computeIncomeVariance(forMonth: month)
            let budget = try Persistence.computeBudgetAndObligationSummary(forMonth: month)
            let totalActual = try Persistence.computeTotalActualSpend(forMonth: month)
            let totalBudgeted = try Persistence.computeTotalBudgetedAllCategories(forMonth: month)
            let recovery = try Persistence.computeRecoveryAdjustments(forMonth: month)
            summary = BudgetSummarySnapshot(
                monthLabel: month,
                plannedIncome: income.planned,
                plannedObligations: budget.plannedObligations,
                discretionaryBudgeted: budget.discretionaryBudgeted,
                discretionaryCapacity: budget.discretionaryCapacity,
                unallocatedDiscretionary: budget.unallocatedDiscretionary,
                totalActualSpend: totalActual,
                totalBudgeted: totalBudgeted,
                recoveryApplied: recovery
            )

            let categoryRows = try Persistence.plannedVsActualByCategory(forMonth: month)
            categories = categoryRows.map { item in
                BudgetCategorySnapshot(name: item.category.name, budgeted: item.budgeted, actual: item.actual, remaining: item.remaining)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func metricRow(label: String, value: Int64, weight: Font.Weight = .regular, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(emphasis ? .primary : .secondary)
            Spacer()
            Text(formatMinorCurrency(value))
                .fontWeight(weight)
                .monospacedDigit()
        }
    }

    private func progressLine(budgeted: Int64, actual: Int64) -> some View {
        let percent = budgeted == 0 ? 0 : min(Double(actual) / Double(budgeted), 1.25)
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: percent)
                .tint(.accentColor)
            HStack {
                Text("Budgeted \(formatMinorCurrency(budgeted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Spent \(formatMinorCurrency(actual))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    BudgetOverviewView()
}
