import SwiftUI

struct BudgetPlannerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMonth: Int = 1
    @State private var selectedYear: Int = Calendar(identifier: .iso8601).component(.year, from: Date())

    @State private var categories: [Category] = []
    @State private var budgetTexts: [String: String] = [:] // categoryId -> text
    @State private var nonDiscretionaryCategories: [Category] = []
    @State private var nonDiscretionaryActuals: [String: Int64] = [:]
    @State private var budgetedMinorByCategory: [String: Int64] = [:]

    @State private var obligationTexts: [String: String] = [:] // categoryId -> text
    @State private var obligationMinorByCategory: [String: Int64] = [:]

    @State private var plannedObligations: Int64 = 0
    @State private var discretionaryCapacity: Int64 = 0

    @State private var plannedIncome: Int64 = 0
    @State private var totalBudgeted: Int64 = 0
    @State private var unallocated: Int64 = 0

    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            plannerContent
                .navigationTitle("Budget Planner")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save All") { saveAll() } }
                }
                .onAppear { initSelection(); load() }
        }
    }

    @ViewBuilder
    private var plannerContent: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Month/Year pickers
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

                // Discretionary
                Text("Discretionary Categories").font(.headline)
                if categories.isEmpty {
                    Text("No discretionary categories yet").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(categories, id: \.id) { cat in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(cat.name)
                                Spacer()
                                TextField("0.00", text: Binding(
                                    get: { budgetTexts[cat.id] ?? formatMinorToDecimalString(budgetedMinorByCategory[cat.id] ?? 0) },
                                    set: { budgetTexts[cat.id] = $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                                .textFieldStyle(.roundedBorder)
                                Button("Save") { save(catId: cat.id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                // Non-discretionary
                Text("Non-discretionary (planned obligations + actual)").font(.headline)
                if nonDiscretionaryCategories.isEmpty {
                    Text("No non-discretionary categories yet").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(nonDiscretionaryCategories, id: \.id) { cat in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.name)
                                    Text("Actual: \(formatMinorToCurrency(nonDiscretionaryActuals[cat.id] ?? 0))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField("0.00", text: Binding(
                                    get: { obligationTexts[cat.id] ?? formatMinorToDecimalString(obligationMinorByCategory[cat.id] ?? 0) },
                                    set: { obligationTexts[cat.id] = $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                                .textFieldStyle(.roundedBorder)
                                Button("Save") { saveObligation(catId: cat.id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                // Summary
                Text("Summary").font(.headline)
                VStack(spacing: 6) {
                    HStack { Text("Planned income"); Spacer(); Text(formatMinorToCurrency(plannedIncome)).monospacedDigit() }
                    HStack { Text("Planned obligations"); Spacer(); Text(formatMinorToCurrency(plannedObligations)).monospacedDigit() }
                    HStack { Text("Discretionary capacity"); Spacer(); Text(formatMinorToCurrency(discretionaryCapacity)).monospacedDigit() }
                    HStack { Text("Discretionary budgeted"); Spacer(); Text(formatMinorToCurrency(totalBudgeted)).monospacedDigit() }
                    HStack { Text("Unallocated discretionary"); Spacer(); Text(formatMinorToCurrency(unallocated)).monospacedDigit() }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .padding()
        }
        #else
        Form {
            Section {
                HStack {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthName(m)).tag(m)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif

                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears(), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif
                }
                .onChange(of: selectedMonth) { load() }
                .onChange(of: selectedYear) { load() }
            }

            Section("Discretionary Categories") {
                if categories.isEmpty {
                    Text("No discretionary categories yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories, id: \.id) { cat in
                        HStack {
                            Text(cat.name)
                            Spacer()
                            TextField("0.00", text: Binding(
                                get: { budgetTexts[cat.id] ?? formatMinorToDecimalString(budgetedMinorByCategory[cat.id] ?? 0) },
                                set: { budgetTexts[cat.id] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            Button("Save") { save(catId: cat.id) }
                        }
                    }
                }
            }

            Section("Non-discretionary (planned obligations + actual)") {
                if nonDiscretionaryCategories.isEmpty {
                    Text("No non-discretionary categories yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nonDiscretionaryCategories, id: \.id) { cat in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                Text("Actual: \(formatMinorToCurrency(nonDiscretionaryActuals[cat.id] ?? 0))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("0.00", text: Binding(
                                get: { obligationTexts[cat.id] ?? formatMinorToDecimalString(obligationMinorByCategory[cat.id] ?? 0) },
                                set: { obligationTexts[cat.id] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            Button("Save") { saveObligation(catId: cat.id) }
                        }
                    }
                }
            }

            Section("Summary") {
                HStack { Text("Planned income"); Spacer(); Text(formatMinorToCurrency(plannedIncome)).monospacedDigit() }
                HStack { Text("Planned obligations"); Spacer(); Text(formatMinorToCurrency(plannedObligations)).monospacedDigit() }
                HStack { Text("Discretionary capacity"); Spacer(); Text(formatMinorToCurrency(discretionaryCapacity)).monospacedDigit() }
                HStack { Text("Discretionary budgeted"); Spacer(); Text(formatMinorToCurrency(totalBudgeted)).monospacedDigit() }
                HStack { Text("Unallocated discretionary"); Spacer(); Text(formatMinorToCurrency(unallocated)).monospacedDigit() }
            }

            if !errorMessage.isEmpty {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        #endif
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
            // Ensure BudgetMonth exists
            _ = try Persistence.fetchOrCreateBudgetMonth(forMonth: month)
            let allCats = try Persistence.listCategories()
            categories = allCats.filter { $0.isDiscretionary }
            nonDiscretionaryCategories = allCats.filter { !$0.isDiscretionary }
            // Load existing plans
            if let bm = try? Persistence.fetchOrCreateBudgetMonth(forMonth: month) {
                let plans = try Persistence.listBudgetPlans(budgetMonthId: bm.id)
                budgetedMinorByCategory = Dictionary(uniqueKeysWithValues: plans.map { ($0.categoryId, $0.amountMinor) })

                // Load existing obligations
                let obligations = try Persistence.listObligations(budgetMonthId: bm.id)
                obligationMinorByCategory = Dictionary(uniqueKeysWithValues: obligations.map { ($0.categoryId, $0.amountMinor) })

                // Pre-fill text fields from current values
                budgetTexts = Dictionary(uniqueKeysWithValues: categories.map { cat in
                    let minor = budgetedMinorByCategory[cat.id] ?? 0
                    return (cat.id, formatMinorToDecimalString(minor))
                })

                // Pre-fill obligation text fields
                for cat in nonDiscretionaryCategories {
                    let minor = obligationMinorByCategory[cat.id] ?? 0
                    obligationTexts[cat.id] = formatMinorToDecimalString(minor)
                }
            } else {
                budgetedMinorByCategory = [:]
                obligationMinorByCategory = [:]
                budgetTexts = [:]
                obligationTexts = [:]
            }

            // Compute actuals for non-discretionary categories
            var ndActuals: [String: Int64] = [:]
            for cat in nonDiscretionaryCategories {
                let actual = try Persistence.computeActualSpend(forMonth: month, categoryId: cat.id)
                ndActuals[cat.id] = actual
            }
            nonDiscretionaryActuals = ndActuals

            let summary = try Persistence.computeBudgetAndObligationSummary(forMonth: month)
            plannedIncome = summary.plannedIncome
            plannedObligations = summary.plannedObligations
            discretionaryCapacity = summary.discretionaryCapacity
            totalBudgeted = summary.discretionaryBudgeted
            unallocated = summary.unallocatedDiscretionary
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func save(catId: String) {
        let month = monthString()
        guard let text = budgetTexts[catId], let minor = parseCurrencyToMinor(text) else { return }
        do {
            try Persistence.upsertBudgetAmount(forMonth: month, categoryId: catId, amountMinor: minor)
            budgetedMinorByCategory[catId] = minor
            refreshSummary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func saveAll() {
        let month = monthString()
        do {
            // Save discretionary budgets
            for (catId, text) in budgetTexts {
                if let minor = parseCurrencyToMinor(text) {
                    try Persistence.upsertBudgetAmount(forMonth: month, categoryId: catId, amountMinor: minor)
                    budgetedMinorByCategory[catId] = minor
                }
            }
            // Save non-discretionary obligations
            for (catId, text) in obligationTexts {
                if let minor = parseCurrencyToMinor(text) {
                    try Persistence.upsertObligationAmount(forMonth: month, categoryId: catId, amountMinor: minor)
                    obligationMinorByCategory[catId] = minor
                }
            }
            // Refresh summary after saving both sets
            refreshSummary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func saveObligation(catId: String) {
        let month = monthString()
        guard let text = obligationTexts[catId], let minor = parseCurrencyToMinor(text) else { return }
        do {
            try Persistence.upsertObligationAmount(forMonth: month, categoryId: catId, amountMinor: minor)
            obligationMinorByCategory[catId] = minor
            refreshSummary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func refreshSummary() {
        do {
            let summary = try Persistence.computeBudgetAndObligationSummary(forMonth: monthString())
            plannedIncome = summary.plannedIncome
            plannedObligations = summary.plannedObligations
            discretionaryCapacity = summary.discretionaryCapacity
            totalBudgeted = summary.discretionaryBudgeted
            unallocated = summary.unallocatedDiscretionary
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

    private func formatMinorToDecimalString(_ minor: Int64) -> String {
        let amount = Double(minor) / 100.0
        return String(format: "%.2f", amount)
    }

    private func parseCurrencyToMinor(_ text: String) -> Int64? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            return Int64(round(number.doubleValue * 100))
        }
        return nil
    }
}
