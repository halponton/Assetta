import SwiftUI

struct CategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif
    @State private var categories: [Category] = []
    @State private var errorMessage: String?

    @State private var pendingDelete: Category?
    @State private var showingDeleteConfirm = false

    @State private var newCategoryName: String = ""
    @State private var newCategoryIsDiscretionary: Bool = true
    @State private var isSavingNewCategory: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                Button("Reload") { reload() }
                #if os(iOS)
                Button(editMode?.wrappedValue.isEditing == true ? "Done" : "Edit") {
                    withAnimation {
                        if editMode?.wrappedValue.isEditing == true {
                            editMode?.wrappedValue = .inactive
                        } else {
                            editMode?.wrappedValue = .active
                        }
                    }
                }
                #endif
                Button("Close") { dismiss() }
            }
            .padding()

            if let message = errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .padding([.horizontal, .bottom])
            }

            List {
                Section("Add Category") {
                    HStack(spacing: 12) {
                        TextField("Name", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Discretionary", isOn: $newCategoryIsDiscretionary)
                        Button {
                            addCategory()
                        } label: {
                            if isSavingNewCategory {
                                ProgressView()
                            } else {
                                Text("Add")
                            }
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNewCategory)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Add Category")
                }

                Section("Existing Categories") {
                    ForEach(categories, id: \.id) { cat in
                        HStack {
                            Text(cat.name)
                            Spacer()
                            Text(cat.isDiscretionary ? "Discretionary" : "Non-discretionary")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = cat
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = cat
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: requestDelete)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                reload()
            }
        }
        .confirmationDialog(
            "Delete Category?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func reload() {
        do {
            let new = try Persistence.listCategories()
            withAnimation(.none) {
                categories = new
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingNewCategory = true
        do {
            try Persistence.createCategory(name: name, isDiscretionary: newCategoryIsDiscretionary)
            newCategoryName = ""
            newCategoryIsDiscretionary = true
            // Defer reload slightly to avoid layout churn
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: Notification.Name("CategoriesDidChange"), object: nil)
                reload()
                isSavingNewCategory = false
            }
        } catch {
            errorMessage = String(describing: error)
            isSavingNewCategory = false
        }
    }

    private func requestDelete(at offsets: IndexSet) {
        if let index = offsets.first, categories.indices.contains(index) {
            pendingDelete = categories[index]
            showingDeleteConfirm = true
        }
    }

    private func confirmDelete() {
        guard let cat = pendingDelete else { return }
        do {
            try Persistence.deleteCategory(id: cat.id)
            // Optimistically update UI
            categories.removeAll { $0.id == cat.id }
            NotificationCenter.default.post(name: Notification.Name("CategoriesDidChange"), object: nil)
            pendingDelete = nil
        } catch PersistenceError.categoryInUse {
            errorMessage = "This category is used by one or more transactions and cannot be deleted."
            pendingDelete = nil
        } catch {
            errorMessage = String(describing: error)
            pendingDelete = nil
        }
    }
}

