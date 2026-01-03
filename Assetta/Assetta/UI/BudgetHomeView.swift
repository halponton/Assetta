import SwiftUI

struct BudgetHomeView: View {
    @State private var monthLabel: String = ""
    @State private var plannedIncome: Int64 = 0
    @State private var totalBudgeted: Int64 = 0
    @State private var totalActualSpend: Int64 = 0
    @State private var unallocated: Int64 = 0
    @State private var recoveryApplied: Int64 = 0
    @State private var categories: [CategoryBudgetSnapshot] = []
    @State private var showingPlanner = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Budget")
                                        .font(.headline)
                                    Text(monthLabel)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Open planner") { showingPlanner = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            SummaryRow(title: "Planned income", value: formatCurrency(plannedIncome))
                            SummaryRow(title: "Budgeted", value: formatCurrency(totalBudgeted))
                            SummaryRow(title: "Spent", value: formatCurrency(totalActualSpend))
                            SummaryRow(title: "Unallocated income", value: formatCurrency(unallocated), emphasis: unallocated != 0)
                            if recoveryApplied > 0 {
                                SummaryRow(title: "Recovery applied", value: formatCurrency(recoveryApplied), emphasis: true)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Categories")
                                .font(.headline)
                            if categories.isEmpty {
                                Text("No categories planned yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(categories, id: \.category.id) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(item.category.name)
                                                Spacer()
                                                Text(formatCurrency(item.remaining))
                                                    .monospacedDigit()
                                                    .foregroundStyle(item.remaining < 0 ? .pink : .secondary)
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            HStack {
                                                Text("Budgeted")
                                                Spacer()
                                                Text(formatCurrency(item.planned))
                                                    .monospacedDigit()
                                            }
                                            .foregroundStyle(.secondary)
                                            HStack {
                                                Text("Actual")
                                                Spacer()
                                                Text(formatCurrency(item.actual))
                                                    .monospacedDigit()
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
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
            .sheet(isPresented: $showingPlanner) {
                BudgetPlannerView()
                #if os(macOS)
                    .frame(minWidth: 700, minHeight: 520)
                #else
                    .frame(minWidth: 420)
                #endif
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .navigationTitle("Budget")
        }
    }

    private func load() async {
        do {
            let month = currentMonth()
            let label = formattedMonthLabel(for: month)
            let income = try Persistence.computeIncomeVariance(forMonth: month)
            let summary = try Persistence.computeBudgetSummary(forMonth: month)
            let overspend = try Persistence.computeMonthlyOverspend(forMonth: month)
            let recovery = try Persistence.computeRecoveryAdjustments(forMonth: month)
            let budgetMonth = try Persistence.fetchOrCreateBudgetMonth(forMonth: month)
            let plans = try Persistence.listBudgetPlans(budgetMonthId: budgetMonth.id)
            let categoriesList = try Persistence.listCategories()

            var snapshots: [CategoryBudgetSnapshot] = []
            for plan in plans {
                if let category = categoriesList.first(where: { $0.id == plan.categoryId }) {
                    let actual = try Persistence.computeActualSpend(forMonth: month, categoryId: category.id)
                    snapshots.append(CategoryBudgetSnapshot(category: category, planned: plan.amountMinor, actual: actual))
                }
            }

            await MainActor.run {
                monthLabel = label
                plannedIncome = income.planned
                totalBudgeted = overspend.totalBudgeted
                totalActualSpend = overspend.totalActual
                recoveryApplied = recovery
                unallocated = summary.unallocated + max(income.variance, 0)
                categories = snapshots
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
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

private struct CategoryBudgetSnapshot {
    let category: Category
    let planned: Int64
    let actual: Int64

    var remaining: Int64 { planned - actual }
}
