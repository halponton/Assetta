import Foundation
import GRDB

struct ObligationPlan: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Hashable {
    static let databaseTableName = "obligation_plan"

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
