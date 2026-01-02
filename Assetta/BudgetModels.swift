import Foundation
import GRDB

struct BudgetMonth: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Identifiable, Hashable {
    static let databaseTableName = "budget_month"

    var id: String
    var workspaceId: Int64
    var month: String // YYYY-MM
    var createdAt: String

    enum Columns: String, ColumnExpression {
        case id
        case workspace_id
        case month
        case created_at
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case month
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        workspaceId: Int64,
        month: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.month = month
        self.createdAt = createdAt
    }
}

struct BudgetCategoryPlan: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Hashable {
    static let databaseTableName = "budget_category_plan"

    var budgetMonthId: String
    var categoryId: String
    var amountMinor: Int64

    enum Columns: String, ColumnExpression {
        case budget_month_id
        case category_id
        case amount_minor
    }

    enum CodingKeys: String, CodingKey {
        case budgetMonthId = "budget_month_id"
        case categoryId = "category_id"
        case amountMinor = "amount_minor"
    }

    init(budgetMonthId: String, categoryId: String, amountMinor: Int64) {
        self.budgetMonthId = budgetMonthId
        self.categoryId = categoryId
        self.amountMinor = amountMinor
    }
}
