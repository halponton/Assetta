import Foundation
import GRDB

struct IncomePlan: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Identifiable, Hashable {
    var id: String
    var workspaceId: Int64
    var month: String
    var plannedAmountMinor: Int64
    var createdAt: String

    static let databaseTableName = "income_plan"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workspaceId = Column(CodingKeys.workspaceId)
        static let month = Column(CodingKeys.month)
        static let plannedAmountMinor = Column(CodingKeys.plannedAmountMinor)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case month
        case plannedAmountMinor = "planned_amount_minor"
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        workspaceId: Int64,
        month: String,
        plannedAmountMinor: Int64,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.month = month
        self.plannedAmountMinor = plannedAmountMinor
        self.createdAt = createdAt
    }
}
