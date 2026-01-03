import SwiftUI

struct RecoveryOverviewView: View {
    @State private var schedules: [RecoverySchedule] = []
    @State private var errorMessage: String?
    @State private var showingManage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recovery")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                GlassCard(title: "Active schedules") {
                    if schedules.isEmpty {
                        Text("No active recovery schedules")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(schedules, id: \.id) { schedule in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(schedule.sourceType.rawValue.capitalized)
                                        .font(.headline)
                                    HStack {
                                        Text("Start")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(schedule.startMonth)
                                            .monospacedDigit()
                                    }
                                    HStack {
                                        Text("Duration")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(schedule.durationMonths) months")
                                            .monospacedDigit()
                                    }
                                    HStack {
                                        Text("Monthly adjustment")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(formatMinorCurrency(schedule.monthlyAdjustmentMinor))
                                            .monospacedDigit()
                                    }
                                }
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(.regularMaterial)
        .navigationTitle("Recovery")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Manage") { showingManage = true }
                Button(action: reload) { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showingManage) {
            RecoverySchedulesView()
        }
        .task { reload() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }) {
            if let message = errorMessage { Text(message) }
        }
    }

    private func reload() {
        do {
            schedules = try Persistence.listActiveRecoverySchedules()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

#Preview {
    RecoveryOverviewView()
}
