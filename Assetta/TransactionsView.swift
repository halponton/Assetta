import SwiftUI

struct TransactionsView: View {
    let account: Account

    @State private var transactions: [Transaction] = []
    @State private var showingAdd = false
    @State private var errorMessage: String?

    @State private var selectedTransaction: Transaction?
    @State private var showingEdit = false
    @State private var pendingDelete: Transaction?
    @State private var showingDeleteConfirm = false

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
                            pendingDelete = tx
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = tx
                            showingDeleteConfirm = true
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
            #if os(macOS)
            .keyboardShortcut("n", modifiers: [.command])
            #endif
        }
        .sheet(isPresented: $showingAdd) {
            AddTransactionView(account: account) { didCreate in
                if didCreate { reload() }
            }
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $showingEdit, onDismiss: { selectedTransaction = nil }) {
            if let tx = selectedTransaction, let initial = editInitialState(for: tx) {
                EditTransactionView(initial: initial) { result in
                    switch result {
                    case .cancel:
                        break
                    case .saved:
                        reload()
                    }
                }
                .frame(minWidth: 420)
            } else {
                Text("No transaction selected")
            }
        }
        .task { reload() }
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
        #if os(macOS)
        .onDeleteCommand(perform: handleDeleteCommand)
        #endif
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
    }

    private func reload() {
        do { transactions = try Persistence.listTransactions(accountId: account.id) } catch { errorMessage = String(describing: error) }
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
            notes: tx.notes
        )
    }

    private func confirmDelete() {
        guard let tx = pendingDelete else { return }
        do {
            try Persistence.deleteTransaction(id: tx.id)
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

    #if os(macOS)
    private func handleDeleteCommand() {
        if let tx = selectedTransaction {
            pendingDelete = tx
            showingDeleteConfirm = true
        }
    }
    #endif
}

struct EditTransactionInitialState {
    let id: String
    var date: Date
    var amountMajor: Decimal
    var type: Transaction.TransactionType
    var notes: String?
}

enum EditTransactionResult { case cancel, saved }

private struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: EditTransactionInitialState
    var onComplete: (EditTransactionResult) -> Void

    @State private var date: Date
    @State private var amountMajorText: String
    @State private var type: Transaction.TransactionType
    @State private var notes: String
    @State private var errorMessage: String?

    init(initial: EditTransactionInitialState, onComplete: @escaping (EditTransactionResult) -> Void) {
        self.initial = initial
        self.onComplete = onComplete
        _date = State(initialValue: initial.date)
        _type = State(initialValue: initial.type)
        _notes = State(initialValue: initial.notes ?? "")
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
                    ForEach(Transaction.TransactionType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
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
            }
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
            try Persistence.updateTransaction(id: initial.id, date: date, amountMajor: amount, type: type, notes: notes.isEmpty ? nil : notes)
            dismiss(); onComplete(.saved)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
private struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    var onComplete: (Bool) -> Void

    @State private var date: Date = Date()
    @State private var amountMajorText: String = ""
    @State private var type: Transaction.TransactionType = .purchase
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
                    ForEach(Transaction.TransactionType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
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
            }
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
            try Persistence.createTransaction(accountId: account.id, date: date, amountMajor: amount, type: type, notes: notes.isEmpty ? nil : notes)
            dismiss(); onComplete(true)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

