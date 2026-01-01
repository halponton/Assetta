import Foundation
import GRDB

struct Account: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Identifiable, Hashable {
    static let databaseTableName = "account"

    enum AccountType: String, Codable, CaseIterable, Sendable {
        case current
        case credit
        case savings
        case investment
    }

    var id: String
    var workspaceId: Int64
    var name: String
    var type: AccountType
    var institution: String?
    var createdAt: String

    enum Columns: String, ColumnExpression {
        case id
        case workspace_id
        case name
        case type
        case institution
        case created_at
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case name
        case type
        case institution
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        workspaceId: Int64,
        name: String,
        type: AccountType,
        institution: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.type = type
        self.institution = institution
        self.createdAt = createdAt
    }
}
