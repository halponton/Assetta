import SwiftUI

struct RecoveryOverviewView: View {
    @State private var schedules: [RecoverySchedule] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recovery")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active schedules")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if schedules.isEmpty {
                            Text("No active recovery schedules")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(schedules, id: \.id) { schedule in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(title(for: schedule))
                                            .font(.headline)
                                        Text("Starts \(schedule.startMonth) • \(schedule.durationMonths) months")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                        Text("Monthly adjustment \(formatMinorToCurrency(schedule.monthlyAdjustmentMinor))")
                                            .monospacedDigit()
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

    private func title(for schedule: RecoverySchedule) -> String {
        switch schedule.sourceType {
        case .overspend:
            return "Overspend recovery"
        case .savings_withdrawal:
            return "Savings withdrawal recovery"
        }
    }

    @MainActor
    private func reload() async {
        do {
            schedules = try Persistence.listActiveRecoverySchedules()
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load recovery schedules: \(error.localizedDescription)"
            schedules = []
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

