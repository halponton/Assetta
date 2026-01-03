import SwiftUI

struct RecoveryHomeView: View {
    @State private var schedules: [RecoverySchedule] = []
    @State private var errorMessage: String?
    @State private var showingManage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery")
                        .font(.largeTitle.bold())
                    Text("Calm acknowledgement of obligations")
                        .foregroundStyle(.secondary)
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Active schedules")
                                .font(.headline)
                            Spacer()
                            Button("Manage") { showingManage = true }
                                .buttonStyle(.bordered)
                        }
                        if schedules.isEmpty {
                            Text("No active recovery right now")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(schedules, id: \.id) { schedule in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(schedule.sourceType.rawValue.capitalized)
                                                .font(.headline)
                                            Text("Starts \(formatMonthYear(from: schedule.startMonth)) · \(schedule.durationMonths) months")
                                                .foregroundStyle(.secondary)
                                            Text("Monthly adjustment: \(formatMinorToCurrency(minor: schedule.monthlyAdjustmentMinor))")
                                                .font(.subheadline)
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in reload() }
        .sheet(isPresented: $showingManage) {
            RecoverySchedulesView()
                .frame(minWidth: 720, minHeight: 520)
        }
    }

    private func reload() {
        do {
            schedules = try Persistence.listActiveRecoverySchedules()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func formatMinorToCurrency(minor: Int64) -> String {
        let number = NSDecimalNumber(value: minor).dividing(by: 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private func formatMonthYear(from monthInt: Int) -> String {
        let year = monthInt / 100
        let month = monthInt % 100
        let comps = DateComponents(year: year, month: month)
        let calendar = Calendar.current
        if let date = calendar.date(from: comps) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
        return "\(year)-\(String(format: "%02d", month))"
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

