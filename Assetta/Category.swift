import Foundation
import GRDB

struct Category: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Identifiable, Hashable {
    static let databaseTableName = "category"

    var id: String
    var workspaceId: Int64
    var name: String
    var isSystem: Bool
    var isDiscretionary: Bool
    var sortOrder: Int
    var createdAt: String

    enum Columns: String, ColumnExpression {
        case id
        case workspace_id
        case name
        case is_system
        case is_discretionary
        case sort_order
        case created_at
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case name
        case isSystem = "is_system"
        case isDiscretionary = "is_discretionary"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        workspaceId: Int64,
        name: String,
        isSystem: Bool = false,
        isDiscretionary: Bool = true,
        sortOrder: Int = 0,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.isSystem = isSystem
        self.isDiscretionary = isDiscretionary
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
