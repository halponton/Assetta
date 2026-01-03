import SwiftUI

struct RecoveryHomeView: View {
    @State private var schedules: [RecoverySchedule] = []
    @State private var showingManager = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recovery")
                                    .font(.headline)
                                Spacer()
                                Button("Manage") { showingManager = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            SummaryRow(title: "Active schedules", value: "\(schedules.count)")
                            SummaryRow(title: "Pressure this month", value: formatCurrency(monthlyPressure), emphasis: monthlyPressure > 0)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Schedules")
                                .font(.headline)
                            if schedules.isEmpty {
                                Text("No active recovery schedules")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(schedules, id: \.id) { schedule in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(schedule.sourceType.rawValue.capitalized)
                                                Spacer()
                                                Text(formatCurrency(schedule.monthlyAdjustmentMinor))
                                                    .monospacedDigit()
                                                    .foregroundStyle(.secondary)
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            Text("Starts \(schedule.startMonth) · \(schedule.durationMonths) month\(schedule.durationMonths == 1 ? "" : "s")")
                                                .foregroundStyle(.secondary)
                                                .font(.footnote)
                                        }
                                        .padding(.vertical, 4)
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
            .sheet(isPresented: $showingManager) {
                RecoverySchedulesView()
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
            .navigationTitle("Recovery")
        }
    }

    private var monthlyPressure: Int64 {
        schedules.reduce(0) { $0 + $1.monthlyAdjustmentMinor }
    }

    private func load() async {
        do {
            let list = try Persistence.listActiveRecoverySchedules()
            await MainActor.run { schedules = list }
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
}
