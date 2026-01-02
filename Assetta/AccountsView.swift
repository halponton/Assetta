import SwiftUI

struct AccountsView: View {
    @State private var accounts: [Account] = []
    @State private var savingsBalances: [String: Int64] = [:]
    @State private var selected: Account?
    @SceneStorage("selectedAccountId") private var selectedAccountId: String?
    @State private var showingAdd = false
    @State private var showingCategories = false
    @State private var showingIncomePlan = false
    @State private var showingBudgetPlanner = false
    @State private var errorMessage: String?
    #if DEBUG
    @State private var showingDebug = false
    #endif

    var body: some View {
        NavigationSplitView {
            if accounts.isEmpty {
                VStack(spacing: 8) {
                    Text("No accounts available")
                        .foregroundStyle(.secondary)
                    Button("Add Account") { showingAdd = true }
#if os(macOS)
                    .keyboardShortcut("n", modifiers: [.command])
#endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selected) {
                    Section("Spending & Other Accounts") {
                        ForEach(accounts.filter { $0.type != .savings }, id: \.id) { account in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(account.type.rawValue)
                                        .foregroundStyle(.secondary)
                                    if let inst = account.institution, !inst.isEmpty {
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                        Text(inst)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.subheadline)
                            }
                            .tag(account)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = account
                                selectedAccountId = account.id
                            }
                        }
                    }
                    Section("Savings") {
                        ForEach(accounts.filter { $0.type == .savings }, id: \.id) { account in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        Text(account.type.rawValue)
                                            .foregroundStyle(.secondary)
                                        if let inst = account.institution, !inst.isEmpty {
                                            Text("·")
                                                .foregroundStyle(.secondary)
                                            Text(inst)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                                Spacer()
                                Text(formatMinorToCurrency(savingsBalances[account.id] ?? 0))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .tag(account)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = account
                                selectedAccountId = account.id
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Accounts")
                .toolbar {
                    Button("Add Account") { showingAdd = true }
#if os(macOS)
                    .keyboardShortcut("n", modifiers: [.command])
#endif
                    Button("Manage Categories") { DispatchQueue.main.async { showingCategories = true } }
                    Button("Income Plan") { showingIncomePlan = true }
                    Button("Budget Planner") { showingBudgetPlanner = true }
                    #if DEBUG
                    Button("Debug") { showingDebug = true }
                    #endif
                }
            }
        } detail: {
            if let selected {
                TransactionsView(account: selected)
            } else {
                Text("Select an account")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddAccountView { didCreate in
                if didCreate {
                    DispatchQueue.main.async {
                        reload()
                        if selected == nil, let id = accounts.last?.id {
                            selectedAccountId = id
                            selected = accounts.last
                        }
                    }
                }
            }
            .frame(minWidth: 360)
        }
        .sheet(isPresented: $showingCategories) {
            CategoriesView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $showingIncomePlan) {
            IncomePlanView()
            #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
            #else
                .frame(minWidth: 420)
            #endif
        }
        .sheet(isPresented: $showingBudgetPlanner) {
            BudgetPlannerView()
            #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
            #else
                .frame(minWidth: 420)
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showingDebug) {
            DebugToolsView()
                .frame(minWidth: 420, minHeight: 240)
        }
        #endif
        .task {
            reload()
            if selected == nil, let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
                selected = acc
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in
            reload()
        }
        #if DEBUG
        .onChange(of: showingDebug) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                reload()
            }
        }
        #endif
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private func reload() {
        do {
            accounts = try Persistence.listAccounts()
            // Precompute savings balances
            var balances: [String: Int64] = [:]
            for acc in accounts where acc.type == .savings {
                balances[acc.id] = try Persistence.computeSavingsBalance(accountId: acc.id)
            }
            savingsBalances = balances
            if selected == nil, let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
                selected = acc
            }
        } catch {
            errorMessage = String(describing: error)
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

private struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    var onComplete: (Bool) -> Void

    @State private var name = ""
    @State private var type: Account.AccountType = .current
    @State private var institution: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(Account.AccountType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    TextField("Institution (optional)", text: $institution)
                }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onComplete(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
        }
    }

    private func save() {
        do {
            try Persistence.createAccount(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, institution: institution.isEmpty ? nil : institution)
            dismiss(); onComplete(true)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

#if DEBUG
private struct DebugToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalTransactions: Int = 0
    @State private var totalBudgetPlans: Int = 0
    @State private var totalObligations: Int = 0
    @State private var errorMessage: String?
    @State private var showingConfirm = false
    @State private var showingConfirmClearPlans = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Database") {
                    HStack { Text("Total transactions"); Spacer(); Text(String(totalTransactions)).monospacedDigit() }
                    HStack { Text("Budget plans (discretionary)"); Spacer(); Text(String(totalBudgetPlans)).monospacedDigit() }
                    HStack { Text("Obligations (non-discretionary)"); Spacer(); Text(String(totalObligations)).monospacedDigit() }
                }
                Section("Danger Zone") {
                    Button(role: .destructive) { showingConfirm = true } label: {
                        Text("Delete ALL transactions")
                    }
                    Button(role: .destructive) { showingConfirmClearPlans = true } label: {
                        Text("Delete ALL budget plans & obligations")
                    }
                }
                if let msg = errorMessage { Section { Text(msg).foregroundStyle(.red) } }
            }
            .navigationTitle("Debug Tools")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { reloadCounts() }
            .confirmationDialog("Delete ALL transactions?", isPresented: $showingConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteAllTransactions() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .confirmationDialog("Delete ALL budget plans & obligations?", isPresented: $showingConfirmClearPlans, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteAllPlans() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func reloadCounts() {
        do {
            totalTransactions = try Persistence.countAllTransactions()
            totalBudgetPlans = try Persistence.countAllBudgetPlans()
            totalObligations = try Persistence.countAllObligations()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteAllTransactions() {
        do {
            try Persistence.deleteAllTransactions()
            reloadCounts()
            NotificationCenter.default.post(name: Notification.Name("TransactionsDidChange"), object: nil)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteAllPlans() {
        do {
            try Persistence.deleteAllBudgetPlans()
            try Persistence.deleteAllObligations()
            reloadCounts()
            NotificationCenter.default.post(name: Notification.Name("BudgetPlansDidChange"), object: nil)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
#endif

