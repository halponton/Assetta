import SwiftUI

struct RecoverySchedulesView: View {
    @State private var schedules: [RecoverySchedule] = []
    @State private var showingAdd = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(schedules, id: \.id) { schedule in
                VStack(alignment: .leading) {
                    Text("\(schedule.sourceType.rawValue) - \(schedule.sourceId)")
                    Text("Start: \(schedule.startMonth)")
                    Text("Duration: \(schedule.durationMonths) months")
                    Text("Monthly Adjustment: \(formatMinorToCurrency(minor: schedule.monthlyAdjustmentMinor))")
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Recovery Schedules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        showingAdd = true
                    }
                }
            }
            .onAppear {
                reload()
            }
            .sheet(isPresented: $showingAdd) {
                AddRecoveryScheduleView { didCreate in
                    if didCreate {
                        reload()
                    }
                    showingAdd = false
                }
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 420)
                #endif
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    private func reload() {
        do {
            schedules = try Persistence.listActiveRecoverySchedules()
        } catch {
            errorMessage = "Failed to load schedules: \(error.localizedDescription)"
            schedules = []
        }
    }

    private func formatMonthYear(from monthInt: Int) -> String {
        // monthInt format: YYYYMM, e.g. 202601 for Jan 2026
        let year = monthInt / 100
        let month = monthInt % 100
        let dateComponents = DateComponents(year: year, month: month)
        let calendar = Calendar.current
        if let date = calendar.date(from: dateComponents) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
        return "\(year)-\(String(format: "%02d", month))"
    }
}

private struct AddRecoveryScheduleView: View {
    @Environment(\.dismiss) var dismiss
    let onComplete: (Bool) -> Void

    @State private var sourceType: RecoverySchedule.SourceType = .overspend
    @State private var sourceId: String = ""
    @State private var startMonthYear: Int
    @State private var startMonthIndex: Int
    @State private var duration: Int = 1
    @State private var monthlyText: String = ""
    @State private var errorMessage: String?
    @State private var overspendMinor: Int64? = nil

    private let years: [Int]

    init(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        if let month = comps.month, let year = comps.year {
            var nextMonth = month + 1
            var nextYear = year
            if nextMonth > 12 {
                nextMonth = 1
                nextYear += 1
            }
            _startMonthYear = State(initialValue: nextYear)
            _startMonthIndex = State(initialValue: nextMonth)
            years = Array(year...year + 5)
        } else {
            let currentYear = cal.component(.year, from: now)
            _startMonthYear = State(initialValue: currentYear)
            _startMonthIndex = State(initialValue: cal.component(.month, from: now))
            years = Array(currentYear...currentYear + 5)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source Type", selection: $sourceType) {
                    Text("Overspend").tag(RecoverySchedule.SourceType.overspend)
                    Text("Savings Withdrawal").tag(RecoverySchedule.SourceType.savings_withdrawal)
                }
                .onChange(of: sourceType) { _, _ in recalcOverspendAndMonthly() }

                if sourceType == .savings_withdrawal {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Withdrawal Transaction ID", text: $sourceId)
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
#endif
                        Text("Use the transaction.id of the savings withdrawal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Picker("Month", selection: $startMonthIndex) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(from: month)).tag(month)
                        }
                    }
                    .onChange(of: startMonthIndex) { _, _ in recalcOverspendAndMonthly() }

                    Picker("Year", selection: $startMonthYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .onChange(of: startMonthYear) { _, _ in recalcOverspendAndMonthly() }
                }
                Text("Start must be strictly after the source month")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                if sourceType == .overspend {
                    let prev = previousMonth(year: startMonthYear, month: startMonthIndex)
                    Text("Overspend in \(monthName(from: prev.month)) \(prev.year): \(formatMinorToCurrency(minor: overspendMinor ?? 0))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker("Duration (months)", selection: $duration) {
                    ForEach(1...3, id: \.self) { i in
                        Text("\(i)").tag(i)
                    }
                }
                .onChange(of: duration) { _, _ in
                    recalcOverspendAndMonthly()
                }

                TextField("Monthly Amount", text: $monthlyText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
            .navigationTitle("Add Recovery Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                recalcOverspendAndMonthly()
            }
        }
    }

    private func monthName(from month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[month - 1]
    }

    private func save() {
        guard let monthlyAdjustmentMinor = parseMonthlyTextToMinor(monthlyText) else {
            errorMessage = "Monthly amount is invalid."
            return
        }

        let startMonth = String(format: "%04d-%02d", startMonthYear, startMonthIndex)
        let prev = previousMonth(year: startMonthYear, month: startMonthIndex)
        let overspendSourceMonth = String(format: "%04d-%02d", prev.year, prev.month)

        let sourceIdToUse: String
        if sourceType == .overspend {
            sourceIdToUse = overspendSourceMonth
        } else {
            let trimmed = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errorMessage = "Source ID cannot be empty."
                return
            }
            sourceIdToUse = trimmed
        }

        do {
            try Persistence.createRecoverySchedule(
                sourceType: sourceType,
                sourceId: sourceIdToUse,
                startMonth: startMonth,
                durationMonths: duration,
                monthlyAdjustmentMinor: monthlyAdjustmentMinor
            )
            dismiss()
            onComplete(true)
        } catch {
            errorMessage = "Failed to create schedule: \(error.localizedDescription)"
        }
    }

    private func parseMonthlyTextToMinor(_ text: String) -> Int64? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            let decimal = NSDecimalNumber(decimal: number.decimalValue)
            let minorDecimal = decimal.multiplying(by: 100)
            return minorDecimal.int64Value
        }
        return nil
    }

    private func previousMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        var y = year
        var m = month - 1
        if m < 1 {
            m = 12
            y -= 1
        }
        return (y, m)
    }

    private func formatMinorToCurrency(minor: Int64) -> String {
        let amount = Double(minor) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private func formatMinorToDecimalString(_ minor: Int64) -> String {
        let amount = Double(minor) / 100.0
        return String(format: "%.2f", amount)
    }

    private func recalcOverspendAndMonthly() {
        guard sourceType == .overspend else {
            overspendMinor = nil
            return
        }
        let prev = previousMonth(year: startMonthYear, month: startMonthIndex)
        let overspendMonth = String(format: "%04d-%02d", prev.year, prev.month)
        do {
            let summary = try Persistence.computeMonthlyOverspend(forMonth: overspendMonth)
            let overspend = max(Int64(0), summary.overspend)
            overspendMinor = overspend
            if overspend > 0 {
                let d = max(1, duration)
                let perMonth = (overspend + Int64(d - 1)) / Int64(d) // round up
                monthlyText = formatMinorToDecimalString(perMonth)
            } else {
                // No overspend; clear suggestion
                // Leave monthlyText as-is if user typed something
            }
        } catch {
            overspendMinor = nil
        }
    }
}

private func formatMinorToCurrency(minor: Int64) -> String {
    let amount = Double(minor) / 100.0
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
}
