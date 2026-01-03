import SwiftUI

struct BudgetOverviewView: View {
    @State private var plannedIncome: Int64 = 0
    @State private var totalBudgeted: Int64 = 0
    @State private var unallocated: Int64 = 0
    @State private var recoveryApplied: Int64 = 0
    @State private var categoryRows: [(category: Category, budgeted: Int64, actual: Int64, remaining: Int64)] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Budget")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plan")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        labelledValue("Planned income", plannedIncome)
                        labelledValue("Total budgeted", totalBudgeted)
                        labelledValue("Unallocated", unallocated)
                        if recoveryApplied > 0 {
                            labelledValue("Recovery this month", recoveryApplied)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if categoryRows.isEmpty {
                            Text("No categories yet")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(categoryRows, id: \.category.id) { row in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(row.category.name)
                                            .font(.subheadline.weight(.semibold))
                                        ProgressView(value: progressValue(for: row), total: 1)
                                            .tint(row.remaining < 0 ? .red : .accentColor)
                                        HStack(spacing: 12) {
                                            labelledLine("Budgeted", row.budgeted)
                                            labelledLine("Actual", row.actual)
                                            labelledLine(row.remaining < 0 ? "Overspent" : "Remaining", row.remaining)
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
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

    private func labelledValue(_ label: String, _ value: Int64) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(formatMinorToCurrency(value))
                .monospacedDigit()
        }
        .font(.body)
    }

    private func labelledLine(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            Text(formatMinorToCurrency(value))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentMonthString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func progressValue(for row: (category: Category, budgeted: Int64, actual: Int64, remaining: Int64)) -> Double {
        guard row.budgeted != 0 else { return 0 }
        return min(Double(row.actual) / Double(row.budgeted), 1)
    }

    @MainActor
    private func reload() async {
        do {
            let month = currentMonthString()
            let summary = try Persistence.computeBudgetSummary(forMonth: month)
            plannedIncome = summary.plannedIncome
            totalBudgeted = summary.totalBudgeted
            unallocated = summary.unallocated
            recoveryApplied = try Persistence.computeRecoveryAdjustments(forMonth: month)
            categoryRows = try Persistence.plannedVsActualByCategory(forMonth: month)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load budget: \(error.localizedDescription)"
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

