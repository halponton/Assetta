import Foundation
import GRDB

public struct RecoverySchedule: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Identifiable, Hashable {
    public static let databaseTableName = "recovery_schedule"
    
    public enum SourceType: String, Codable, CaseIterable, Sendable {
        case overspend
        case savings_withdrawal
    }
    
    public let id: String
    public let workspaceId: Int64
    public let sourceType: SourceType
    public let sourceId: String
    public let startMonth: String
    public let durationMonths: Int
    public let monthlyAdjustmentMinor: Int64
    public let createdAt: String
    
    public enum Columns: String, ColumnExpression {
        case id
        case workspaceId = "workspace_id"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case startMonth = "start_month"
        case durationMonths = "duration_months"
        case monthlyAdjustmentMinor = "monthly_adjustment_minor"
        case createdAt = "created_at"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case startMonth = "start_month"
        case durationMonths = "duration_months"
        case monthlyAdjustmentMinor = "monthly_adjustment_minor"
        case createdAt = "created_at"
    }
    
    public init(
        id: String = UUID().uuidString,
        workspaceId: Int64,
        sourceType: SourceType,
        sourceId: String,
        startMonth: String,
        durationMonths: Int,
        monthlyAdjustmentMinor: Int64,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.startMonth = startMonth
        self.durationMonths = durationMonths
        self.monthlyAdjustmentMinor = monthlyAdjustmentMinor
        self.createdAt = createdAt
    }
    
    public func isFutureOrCurrentStartMonthComparedTo(_ today: Date) -> Bool {
        // Parse startMonth "YYYY-MM"
        let components = startMonth.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              (1...12).contains(month) else {
            return false
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return false
        }
        
        let todayComponents = calendar.dateComponents([.year, .month], from: today)
        guard let currentMonthDate = calendar.date(from: DateComponents(year: todayComponents.year, month: todayComponents.month, day: 1)) else {
            return false
        }
        
        return startDate >= currentMonthDate
    }
    
    public var endMonthExclusive: String {
        // Parse startMonth "YYYY-MM"
        let components = startMonth.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              (1...12).contains(month) else {
            return startMonth
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endDate = calendar.date(byAdding: .month, value: durationMonths, to: startDate) else {
            return startMonth
        }
        
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)
        if let endYear = endComponents.year, let endMonth = endComponents.month {
            return String(format: "%04d-%02d", endYear, endMonth)
        }
        return startMonth
    }
}
