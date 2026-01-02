import SwiftUI

struct TransactionsView: View {
    let account: Account
    private var isSavingsAccount: Bool { account.type == .savings }

    @State private var transactions: [Transaction] = []
    @State private var showingAdd = false
    @State private var showingSavingsMovement = false
    @State private var errorMessage: String?
    @State private var categoryNamesById: [String: String] = [:]
    @State private var categories: [Category] = []

    @State private var selectedTransaction: Transaction?
    @State private var showingEdit = false
    @State private var pendingDelete: Transaction?
    @State private var showingDeleteConfirm = false
    @State private var showingPairedDeleteConfirm = false

    var body: some View {
        VStack {
            if transactions.isEmpty {
                VStack(spacing: 16) {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                    Button("Add Transaction") {
                        showingAdd = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(transactions, id: \.id, selection: $selectedTransaction) { tx in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let d = isoDate(from: tx.date) {
                                Text(d, style: .date)
                            } else {
                                Text(tx.date)
                            }
                            Spacer()
                            Text(formatAmountMinor(tx.amountMinor))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        HStack(spacing: 6) {
                            Text(tx.type.rawValue)
                            if (tx.type == .purchase || tx.type == .fees_interest), let catId = tx.categoryId, let catName = categoryNamesById[catId] {
                                Text("·")
                                Text(catName)
                            }
                            if let notes = tx.notes, !notes.isEmpty {
                                Text("·")
                                Text(notes)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTransaction = tx
                        showingEdit = true
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            if tx.linkedTransactionId != nil {
                                confirmDeletePaired(tx: tx)
                            } else {
                                pendingDelete = tx
                                showingDeleteConfirm = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            if tx.linkedTransactionId != nil {
                                confirmDeletePaired(tx: tx)
                            } else {
                                pendingDelete = tx
                                showingDeleteConfirm = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            selectedTransaction = tx
                            showingEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            Button("Add Transaction") { showingAdd = true }
            Button("Savings Movement") { showingSavingsMovement = true }
            #if os(macOS)
            .keyboardShortcut("n", modifiers: [.command])
            #endif
        }
        .sheet(isPresented: $showingAdd) {
            AddTransactionView(account: account, categories: categories, isSavingsAccount: isSavingsAccount) { didCreate in
                if didCreate { DispatchQueue.main.async { reload() } }
            }
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $showingSavingsMovement) {
            SavingsMovementView(categories: categories) { didCreate in
                if didCreate { DispatchQueue.main.async { reload() } }
                showingSavingsMovement = false
            }
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $showingEdit, onDismiss: { selectedTransaction = nil }) {
            if let tx = selectedTransaction {
                if tx.linkedTransactionId != nil {
                    if let initial = editPairedInitialState(for: tx) {
                        EditPairedMovementView(initial: initial) { result in
                            switch result {
                            case .cancel:
                                break
                            case .saved:
                                DispatchQueue.main.async { reload() }
                            }
                        }
                        .frame(minWidth: 420)
                    } else {
                        Text("No transaction selected")
                    }
                } else if let initial = editInitialState(for: tx) {
                    EditTransactionView(initial: initial, categories: categories, isSavingsAccount: isSavingsAccount) { result in
                        switch result {
                        case .cancel:
                            break
                        case .saved:
                            DispatchQueue.main.async { reload() }
                        }
                    }
                    .frame(minWidth: 420)
                } else {
                    Text("No transaction selected")
                }
            } else {
                Text("No transaction selected")
            }
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CategoriesDidChange"))) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransactionsDidChange"))) { _ in
            reload()
        }
        .onChange(of: account.id) { oldId, newId in
            selectedTransaction = nil
            transactions = []
            reload()
        }
        .confirmationDialog(
            "Delete Transaction?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete Paired Savings Movement?",
            isPresented: $showingPairedDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Both", role: .destructive) {
                guard pendingDelete != nil else { return }
                confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("Deleting this pair will remove both the savings and current account transactions. This action cannot be undone.")
        }
        #if os(macOS)
        .onDeleteCommand(perform: handleDeleteCommand)
        #endif
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
    }

    private func reload() {
        do {
            transactions = try Persistence.listTransactions(accountId: account.id)
            let cats = try Persistence.listCategories()
            categories = cats
            categoryNamesById = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0.name) })
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func formatAmountMinor(_ minor: Int64) -> String {
        let number = NSDecimalNumber(value: minor).dividing(by: 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }
    
    private func isoDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private func editInitialState(for tx: Transaction) -> EditTransactionInitialState? {
        // Convert ISO date string to Date
        guard let date = isoDate(from: tx.date) else { return nil }
        let major = Decimal(tx.amountMinor) / 100
        return EditTransactionInitialState(
            id: tx.id,
            date: date,
            amountMajor: major,
            type: tx.type,
            categoryId: tx.categoryId,
            notes: tx.notes
        )
    }

    private func editPairedInitialState(for tx: Transaction) -> EditPairedMovementInitialState? {
        guard let date = isoDate(from: tx.date) else { return nil }
        let major = Decimal(tx.amountMinor) / 100
        return EditPairedMovementInitialState(
            id: tx.id,
            date: date,
            amountMajor: major,
            notes: tx.notes
        )
    }

    private func confirmDelete() {
        guard let tx = pendingDelete else { return }
        do {
            if tx.linkedTransactionId != nil {
                try Persistence.deletePairedSavingsMovement(pairMemberId: tx.id)
            } else {
                try Persistence.deleteTransaction(id: tx.id)
            }
            transactions.removeAll { $0.id == tx.id }
            pendingDelete = nil
        } catch PersistenceError.transactionIsLinked {
            errorMessage = "This transaction is linked to another transaction and cannot be deleted yet."
            pendingDelete = nil
        } catch {
            errorMessage = String(describing: error)
            pendingDelete = nil
        }
    }

    private func confirmDeletePaired(tx: Transaction) {
        pendingDelete = tx
        showingPairedDeleteConfirm = true
    }

    #if os(macOS)
    private func handleDeleteCommand() {
        if let tx = selectedTransaction {
            if tx.linkedTransactionId != nil {
                confirmDeletePaired(tx: tx)
            } else {
                pendingDelete = tx
                showingDeleteConfirm = true
            }
        }
    }
    #endif
}

struct EditTransactionInitialState {
    let id: String
    var date: Date
    var amountMajor: Decimal
    var type: Transaction.TransactionType
    var categoryId: String?
    var notes: String?
}

enum EditTransactionResult { case cancel, saved }

private struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: EditTransactionInitialState
    let categories: [Category]
    let isSavingsAccount: Bool
    var onComplete: (EditTransactionResult) -> Void

    @State private var date: Date
    @State private var amountMajorText: String
    @State private var type: Transaction.TransactionType
    @State private var notes: String
    @State private var errorMessage: String?

    @State private var categorySelection: String

    init(initial: EditTransactionInitialState, categories: [Category], isSavingsAccount: Bool, onComplete: @escaping (EditTransactionResult) -> Void) {
        self.initial = initial
        self.categories = categories
        self.isSavingsAccount = isSavingsAccount
        self.onComplete = onComplete
        _date = State(initialValue: initial.date)
        _type = State(initialValue: initial.type)
        _notes = State(initialValue: initial.notes ?? "")
        _categorySelection = State(initialValue: initial.categoryId ?? "")
        // Format initial amount
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: initial.amountMajor)
        _amountMajorText = State(initialValue: formatter.string(from: number) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Amount (e.g. 12.34)", text: $amountMajorText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Type", selection: $type) {
                    ForEach(Transaction.TransactionType.allCases.filter { option in
                        // Always hide savings types here, regardless of account type
                        option != .savings_contribution && option != .savings_withdrawal
                    }, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .onChange(of: type) { oldType, newType in
                    if !(newType == .purchase || newType == .fees_interest) {
                        categorySelection = ""
                    }
                }
                if type == .purchase || type == .fees_interest {
                    Picker("Category", selection: $categorySelection) {
                        Text("No Category").tag("")
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                }
            }
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 4)
                .accessibilityLabel("Notes (optional)")
            Text("To move money into or out of savings, use the 'Savings Movement' button.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); onComplete(.cancel) } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
        }
    }

    private var canSave: Bool {
        parseAmountMajor() != nil
    }

    private func parseAmountMajor() -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: amountMajorText) {
            return number.decimalValue
        }
        // Fallback: manual parse replacing commas
        let cleaned = amountMajorText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }

    private func save() {
        guard let amount = parseAmountMajor() else { return }
        do {
            let catIdToSave: String? = (type == .purchase || type == .fees_interest) ? (categorySelection.isEmpty ? nil : categorySelection) : nil
            try Persistence.updateTransaction(id: initial.id, date: date, amountMajor: amount, type: type, notes: notes.isEmpty ? nil : notes, categoryId: catIdToSave)
            NotificationCenter.default.post(name: Notification.Name("TransactionsDidChange"), object: nil)
            dismiss(); onComplete(.saved)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    let categories: [Category]
    let isSavingsAccount: Bool
    var onComplete: (Bool) -> Void

    init(account: Account, categories: [Category], isSavingsAccount: Bool, onComplete: @escaping (Bool) -> Void) {
        self.account = account
        self.categories = categories
        self.isSavingsAccount = isSavingsAccount
        self.onComplete = onComplete
        _type = State(initialValue: isSavingsAccount ? .savings_contribution : .purchase)
    }

    @State private var date: Date = Date()
    @State private var amountMajorText: String = ""
    @State private var type: Transaction.TransactionType
    @State private var categorySelection: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Amount (e.g. 12.34)", text: $amountMajorText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Type", selection: $type) {
                    ForEach(Transaction.TransactionType.allCases.filter { option in
                        // Always hide savings types here, regardless of account type
                        option != .savings_contribution && option != .savings_withdrawal
                    }, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .onChange(of: type) { oldType, newType in
                    if !(newType == .purchase || newType == .fees_interest) {
                        categorySelection = ""
                    }
                }
                if type == .purchase || type == .fees_interest {
                    Picker("Category", selection: $categorySelection) {
                        Text("No Category").tag("")
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                }
            }
            Text("To move money into or out of savings, use the 'Savings Movement' button.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); onComplete(false) } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
        }
    }

    private var canSave: Bool {
        parseAmountMajor() != nil
    }

    private func parseAmountMajor() -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: amountMajorText) {
            return number.decimalValue
        }
        // Fallback: manual parse replacing commas
        let cleaned = amountMajorText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }

    private func save() {
        guard let amount = parseAmountMajor() else { return }
        do {
            try Persistence.createTransaction(accountId: account.id, date: date, amountMajor: amount, type: type, notes: notes.isEmpty ? nil : notes, categoryId: categorySelection.isEmpty ? nil : categorySelection)
            NotificationCenter.default.post(name: Notification.Name("TransactionsDidChange"), object: nil)
            dismiss(); onComplete(true)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct SavingsMovementView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    var onComplete: (Bool) -> Void
    @State private var savingsAccount: Account? = nil
    @State private var currentAccount: Account? = nil
    @State private var date: Date = Date()
    @State private var amountText: String = ""
    @State private var movementType: MovementType = .contribution
    @State private var errorMessage: String?

    enum MovementType: String, CaseIterable, Identifiable {
        case contribution = "Contribution"
        case withdrawal = "Withdrawal"
        var id: String { rawValue }
    }

    // Simulate fetching accounts -- replace with your persistence / model
    @State private var savingsAccounts: [Account] = []
    @State private var currentAccounts: [Account] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Select Accounts")) {
                    Picker("Savings Account", selection: Binding(get: { savingsAccount }, set: { savingsAccount = $0 })) {
                        Text("Select").tag(Account?.none)
                        ForEach(savingsAccounts, id: \.id) { acc in
                            Text(acc.name).tag(Account?.some(acc))
                        }
                    }
                    Picker("Current Account", selection: Binding(get: { currentAccount }, set: { currentAccount = $0 })) {
                        Text("Select").tag(Account?.none)
                        ForEach(currentAccounts, id: \.id) { acc in
                            Text(acc.name).tag(Account?.some(acc))
                        }
                    }
                }

                Section(header: Text("Movement Details")) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Amount (e.g. 12.34)", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Type", selection: $movementType) {
                        ForEach(MovementType.allCases) { mt in
                            Text(mt.rawValue).tag(mt)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Savings Movement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete(false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }.disabled(!canSave)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
            .task {
                loadAccounts()
            }
        }
    }

    private var canSave: Bool {
        guard savingsAccount != nil, currentAccount != nil else { return false }
        guard parseAmount() != nil else { return false }
        return true
    }

    private func parseAmount() -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: amountText) {
            return number.decimalValue
        }
        let clean = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Decimal(string: clean)
    }

    private func loadAccounts() {
        do {
            let allAccounts = try Persistence.listAccounts()
            savingsAccounts = allAccounts.filter { $0.type == .savings }
            currentAccounts = allAccounts.filter { $0.type != .savings }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func save() {
        guard let savingsAcc = savingsAccount, let currentAcc = currentAccount, let amount = parseAmount() else { return }
        do {
            switch movementType {
            case .contribution:
                try Persistence.createPairedSavingsMovement(savingsAccountId: savingsAcc.id, currentAccountId: currentAcc.id, date: date, amountMajor: amount, isContribution: true)
            case .withdrawal:
                try Persistence.createPairedSavingsMovement(savingsAccountId: savingsAcc.id, currentAccountId: currentAcc.id, date: date, amountMajor: amount, isContribution: false)
            }
            NotificationCenter.default.post(name: Notification.Name("TransactionsDidChange"), object: nil)
            dismiss()
            onComplete(true)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct EditPairedMovementInitialState {
    let id: String
    var date: Date
    var amountMajor: Decimal
    var notes: String?
}

enum EditPairedMovementResult { case cancel, saved }

private struct EditPairedMovementView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: EditPairedMovementInitialState
    var onComplete: (EditPairedMovementResult) -> Void

    @State private var date: Date
    @State private var amountText: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(initial: EditPairedMovementInitialState, onComplete: @escaping (EditPairedMovementResult) -> Void) {
        self.initial = initial
        self.onComplete = onComplete
        _date = State(initialValue: initial.date)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: initial.amountMajor)
        _amountText = State(initialValue: formatter.string(from: number) ?? "")
        _notes = State(initialValue: initial.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Amount (e.g. 12.34)", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.top, 4)
                    .accessibilityLabel("Notes (optional)")
            }
            .navigationTitle("Edit Savings Movement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); onComplete(.cancel) } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
        }
    }

    private var canSave: Bool {
        parseAmount() != nil
    }

    private func parseAmount() -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: amountText) {
            return number.decimalValue
        }
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }

    private func save() {
        guard let amount = parseAmount() else { return }
        do {
            try Persistence.updatePairedSavingsMovement(pairMemberId: initial.id, date: date, amountMajor: amount, notes: notes.isEmpty ? nil : notes)
            NotificationCenter.default.post(name: Notification.Name("TransactionsDidChange"), object: nil)
            dismiss()
            onComplete(.saved)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

