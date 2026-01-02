import SwiftUI

struct IncomePlanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: Int = 1
    @State private var selectedYear: Int = Calendar(identifier: .iso8601).component(.year, from: Date())
    @State private var plannedAmountText: String = ""
    @State private var plannedMinor: Int64 = 0
    @State private var actualMinor: Int64 = 0
    @State private var varianceMinor: Int64 = 0
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
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
                    .onChange(of: selectedMonth) { loadData() }
                    .onChange(of: selectedYear) { loadData() }

                    TextField("Planned Income", text: $plannedAmountText)
                        .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }

                Section {
                    Button("Save") {
                        errorMessage = ""
                        guard let plannedMinorValue = parseCurrencyToMinor(plannedAmountText) else {
                            errorMessage = "Invalid planned income amount"
                            return
                        }
                        plannedMinor = plannedMinorValue
                        let monthString = monthString(year: selectedYear, month: selectedMonth)
                        do {
                            try Persistence.upsertIncomePlan(forMonth: monthString, plannedAmountMinor: plannedMinor)
                            loadData()
                        } catch {
                            errorMessage = "Failed to save income plan"
                        }
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    HStack {
                        Text("Planned")
                        Spacer()
                        Text(formatMinorToCurrency(plannedMinor))
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Actual")
                        Spacer()
                        Text(formatMinorToCurrency(actualMinor))
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Variance")
                        Spacer()
                        Text(formatMinorToCurrency(varianceMinor))
                            .foregroundColor(varianceMinor < 0 ? .red : .green)
                    }
                }
            }
            .navigationTitle("Income Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                let cal = Calendar(identifier: .iso8601)
                let comps = cal.dateComponents([.year, .month], from: Date())
                selectedYear = comps.year ?? selectedYear
                selectedMonth = comps.month ?? selectedMonth
                loadData()
            }
        }
    }

    private func loadData() {
        errorMessage = ""
        let monthString = monthString(year: selectedYear, month: selectedMonth)
        do {
            let plan = try Persistence.fetchOrCreateIncomePlan(forMonth: monthString)
            plannedMinor = plan.plannedAmountMinor
            plannedAmountText = formatMinorToDecimalString(plannedMinor)
            let actual = try Persistence.computeActualIncome(forMonth: monthString)
            actualMinor = actual
            let summary = try Persistence.computeIncomeVariance(forMonth: monthString)
            varianceMinor = summary.variance
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func monthString(year: Int, month: Int) -> String {
        return String(format: "%04d-%02d", year, month)
    }

    private func availableYears() -> [Int] {
        let cal = Calendar(identifier: .iso8601)
        let currentYear = cal.component(.year, from: Date())
        let startYear = 2026
        let endYear = max(currentYear + 5, startYear)
        return Array(startYear...endYear)
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.monthSymbols ?? []
        if month >= 1 && month <= symbols.count {
            return symbols[month - 1]
        }
        return "Month"
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

