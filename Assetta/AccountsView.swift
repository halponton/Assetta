import SwiftUI

struct AccountsView: View {
    @State private var accounts: [Account] = []
    @State private var selected: Account?
    @SceneStorage("selectedAccountId") private var selectedAccountId: String?
    @State private var showingAdd = false
    @State private var showingCategories = false
    @State private var showingIncomePlan = false
    @State private var showingBudgetPlanner = false
    @State private var errorMessage: String?

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
                    ForEach(accounts, id: \.id) { account in
                        NavigationLink(value: account) {
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
                        }
                    }
                }
                .onChange(of: selected) { _, newValue in
                    selectedAccountId = newValue?.id
                }
                .navigationTitle("Accounts")
                .toolbar {
                    Button("Add Account") { showingAdd = true }
#if os(macOS)
                    .keyboardShortcut("n", modifiers: [.command])
#endif
                    Button("Manage Categories") { DispatchQueue.main.async { showingCategories = true } }
                    Button("Income Plan") { showingIncomePlan = true }
                    Button("Budget Planner") { showingBudgetPlanner = true }
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
        .task {
            reload()
            if selected == nil, let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
                selected = acc
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private func reload() {
        do {
            accounts = try Persistence.listAccounts()
            if selected == nil, let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
                selected = acc
            }
        } catch {
            errorMessage = String(describing: error)
        }
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

