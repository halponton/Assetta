import Foundation
import GRDB

/// Transaction represents a single ledger entry in Assetta.
///
/// Semantics:
/// - `purchase` counts as spending.
/// - `card_payment` and `transfer` are movement, not spending.
/// - Savings and investment contributions/withdrawals affect net worth, not budgets.
///
/// This model is storage-only for Milestone 2 (no business logic/UI).
struct Transaction: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Hashable {
    static let databaseTableName = "transaction"

    enum TransactionType: String, Codable, CaseIterable, Sendable, Hashable {
        case purchase
        case income
        case transfer
        case card_payment
        case savings_contribution
        case savings_withdrawal
        case investment_contribution
        case investment_withdrawal
        case fees_interest
    }

    // MARK: - Properties

    /// UUID string identifier
    var id: String

    /// Foreign key to Account.id
    var accountId: String

    /// ISO date (YYYY-MM-DD), constrained by schema to >= 2026-01-01
    var date: String

    /// Amount in minor units (pence), Int64
    var amountMinor: Int64

    /// Transaction type
    var type: TransactionType

    /// Optional category reference
    var categoryId: String?

    /// Optional link to a counterpart transaction
    var linkedTransactionId: String?

    /// Optional free-form notes
    var notes: String?

    /// Creation timestamp (ISO-8601 string)
    var createdAt: String

    // MARK: - Coding Keys (DB columns)

    enum Columns: String, ColumnExpression {
        case id
        case account_id
        case date
        case amount_minor
        case type
        case linked_transaction_id
        case category_id
        case notes
        case created_at
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case date
        case amountMinor = "amount_minor"
        case type
        case categoryId = "category_id"
        case linkedTransactionId = "linked_transaction_id"
        case notes
        case createdAt = "created_at"
    }

    // MARK: - Initializers

    init(
        id: String = UUID().uuidString,
        accountId: String,
        date: String,
        amountMinor: Int64,
        type: TransactionType,
        categoryId: String? = nil,
        linkedTransactionId: String? = nil,
        notes: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amountMinor = amountMinor
        self.type = type
        self.categoryId = categoryId
        self.linkedTransactionId = linkedTransactionId
        self.notes = notes
        self.createdAt = createdAt
    }
}
