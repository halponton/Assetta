import SwiftUI

struct BudgetOverviewView: View {
    @State private var selectedMonth: Int = 1
    @State private var selectedYear: Int = Calendar(identifier: .iso8601).component(.year, from: Date())

    @State private var categories: [Category] = []
    @State private var nonDiscretionaryCategories: [Category] = []
    @State private var budgetedMinorByCategory: [String: Int64] = [:]
    @State private var obligationMinorByCategory: [String: Int64] = [:]
    @State private var discretionaryActuals: [String: Int64] = [:]
    @State private var nonDiscretionaryActuals: [String: Int64] = [:]

    @State private var plannedIncome: Int64 = 0
    @State private var plannedObligations: Int64 = 0
    @State private var recoveryApplied: Int64 = 0
    @State private var discretionaryCapacity: Int64 = 0
    @State private var unallocated: Int64 = 0
    @State private var totalBudgeted: Int64 = 0
    @State private var totalActualSpend: Int64 = 0
    @State private var monthlyOverspend: Int64 = 0

    @State private var showingPlanner = false
    @State private var errorMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Budget")
                        .font(.largeTitle.bold())
                    HStack(spacing: 12) {
                        Picker("Month", selection: $selectedMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(monthName(m)).tag(m)
                            }
                        }
                        Picker("Year", selection: $selectedYear) {
                            ForEach(availableYears(), id: \.self) { y in
                                Text(String(y)).tag(y)
                            }
                        }
                    }
                    .onChange(of: selectedMonth) { load() }
                    .onChange(of: selectedYear) { load() }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Summary")
                                .font(.headline)
                            Spacer()
                            Button("Adjust plan") { showingPlanner = true }
                                .buttonStyle(.bordered)
                        }
                        gridRow(label: "Planned income", value: plannedIncome)
                        gridRow(label: "Planned obligations", value: plannedObligations)
                        if recoveryApplied > 0 {
                            gridRow(label: "Recovery applied", value: recoveryApplied, emphasizeNegative: true)
                        }
                        gridRow(label: "Discretionary capacity", value: discretionaryCapacity)
                        gridRow(label: "Discretionary budgeted", value: totalBudgeted)
                        gridRow(label: "Unallocated income", value: unallocated)
                        gridRow(label: "Actual spend", value: totalActualSpend)
                        if monthlyOverspend > 0 {
                            gridRow(label: "Overspend", value: monthlyOverspend, emphasizeNegative: true)
                        }
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Discretionary")
                            .font(.headline)
                        if categories.isEmpty {
                            Text("No discretionary categories yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(categories, id: \.id) { cat in
                                    categoryRow(
                                        name: cat.name,
                                        budgeted: budgetedMinorByCategory[cat.id] ?? 0,
                                        actual: discretionaryActuals[cat.id] ?? 0
                                    )
                                }
                            }
                        }
                    }
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Obligations")
                            .font(.headline)
                        if nonDiscretionaryCategories.isEmpty {
                            Text("No non-discretionary categories yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(nonDiscretionaryCategories, id: \.id) { cat in
                                    categoryRow(
                                        name: cat.name,
                                        budgeted: obligationMinorByCategory[cat.id] ?? 0,
                                        actual: nonDiscretionaryActuals[cat.id] ?? 0
                                    )
                                }
                            }
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingPlanner) {
            BudgetPlannerView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .onAppear { initSelection(); load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CategoriesDidChange"))) { _ in load() }
    }

    private func initSelection() {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.year, .month], from: Date())
        selectedYear = comps.year ?? selectedYear
        selectedMonth = comps.month ?? selectedMonth
    }

    private func monthString() -> String { String(format: "%04d-%02d", selectedYear, selectedMonth) }

    private func load() {
        errorMessage = ""
        do {
            let month = monthString()
            let allCats = try Persistence.listCategories()
            categories = allCats.filter { $0.isDiscretionary }
            nonDiscretionaryCategories = allCats.filter { !$0.isDiscretionary }

            if let bm = try? Persistence.fetchOrCreateBudgetMonth(forMonth: month) {
                let plans = try Persistence.listBudgetPlans(budgetMonthId: bm.id)
                budgetedMinorByCategory = Dictionary(uniqueKeysWithValues: plans.map { ($0.categoryId, $0.amountMinor) })

                let obligations = try Persistence.listObligations(budgetMonthId: bm.id)
                obligationMinorByCategory = Dictionary(uniqueKeysWithValues: obligations.map { ($0.categoryId, $0.amountMinor) })
            }

            var dActuals: [String: Int64] = [:]
            for cat in categories {
                dActuals[cat.id] = try Persistence.computeActualSpend(forMonth: month, categoryId: cat.id)
            }
            discretionaryActuals = dActuals

            var ndActuals: [String: Int64] = [:]
            for cat in nonDiscretionaryCategories {
                ndActuals[cat.id] = try Persistence.computeActualSpend(forMonth: month, categoryId: cat.id)
            }
            nonDiscretionaryActuals = ndActuals

            let summary = try Persistence.computeBudgetAndObligationSummary(forMonth: month)
            plannedIncome = summary.plannedIncome
            plannedObligations = summary.plannedObligations
            discretionaryCapacity = summary.discretionaryCapacity
            unallocated = summary.unallocatedDiscretionary
            totalBudgeted = summary.discretionaryBudgeted

            let monthly = try Persistence.computeMonthlyOverspend(forMonth: month)
            totalActualSpend = monthly.totalActual
            monthlyOverspend = monthly.overspend

            recoveryApplied = try Persistence.computeRecoveryAdjustments(forMonth: month)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.monthSymbols ?? []
        if month >= 1 && month <= symbols.count { return symbols[month - 1] }
        return "Month"
    }

    private func availableYears() -> [Int] {
        let cal = Calendar(identifier: .iso8601)
        let currentYear = cal.component(.year, from: Date())
        let startYear = 2026
        let endYear = max(currentYear + 5, startYear)
        return Array(startYear...endYear)
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
    private func categoryRow(name: String, budgeted: Int64, actual: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text(formatMinorToCurrency(budgeted))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Spent")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatMinorToCurrency(actual))
                    .monospacedDigit()
            }
            let remaining = budgeted - actual
            HStack {
                Text(remaining >= 0 ? "Remaining" : "Overspent")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatMinorToCurrency(remaining))
                    .monospacedDigit()
                    .foregroundStyle(remaining < 0 ? .pink : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

