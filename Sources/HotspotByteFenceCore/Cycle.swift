import Foundation

public enum CycleError: Error, Equatable {
    case invalidResetDay
    case invalidCalendarDate
    case unrepresentableStart
}

public struct CycleID: Codable, Equatable, Hashable, Sendable {
    public let effectiveDate: String
    public let timeZoneID: String

    public init(effectiveDate: String, timeZoneID: String) {
        self.effectiveDate = effectiveDate
        self.timeZoneID = timeZoneID
    }
}

public struct CycleBoundary: Equatable, Sendable {
    public let effectiveDate: String
    public let timeZoneID: String
    public let startInstant: Date

    public init(effectiveDate: String, timeZoneID: String, startInstant: Date) {
        self.effectiveDate = effectiveDate
        self.timeZoneID = timeZoneID
        self.startInstant = startInstant
    }

    public var id: CycleID {
        CycleID(effectiveDate: effectiveDate, timeZoneID: timeZoneID)
    }
}

public enum CycleCalculator {
    public static func effectiveResetDay(year: Int, month: Int, resetDay: Int) throws -> Int {
        guard (1...31).contains(resetDay), (1...12).contains(month) else {
            throw CycleError.invalidResetDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstDay = calendar.date(from: components),
              let days = calendar.range(of: .day, in: .month, for: firstDay) else {
            throw CycleError.invalidCalendarDate
        }
        return min(resetDay, days.count)
    }

    public static func boundary(
        for now: Date,
        resetDay: Int,
        timeZone: TimeZone
    ) throws -> CycleBoundary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw CycleError.invalidCalendarDate
        }
        let currentEffectiveDay = try effectiveResetDay(year: year, month: month, resetDay: resetDay)
        let target: (year: Int, month: Int)
        if day >= currentEffectiveDay {
            target = (year, month)
        } else if month == 1 {
            target = (year - 1, 12)
        } else {
            target = (year, month - 1)
        }
        let effectiveDay = try effectiveResetDay(year: target.year, month: target.month, resetDay: resetDay)
        let startComponents = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: target.year,
            month: target.month,
            day: effectiveDay,
            hour: 0,
            minute: 0,
            second: 0
        )
        let startInstant: Date
        if let exactStart = calendar.date(from: startComponents) {
            startInstant = exactStart
        } else {
            let noonComponents = DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: target.year,
                month: target.month,
                day: effectiveDay,
                hour: 12
            )
            guard let noon = calendar.date(from: noonComponents) else {
                throw CycleError.unrepresentableStart
            }
            startInstant = calendar.startOfDay(for: noon)
        }
        let dateText = String(format: "%04d-%02d-%02d", target.year, target.month, effectiveDay)
        return CycleBoundary(
            effectiveDate: dateText,
            timeZoneID: timeZone.identifier,
            startInstant: startInstant
        )
    }
}
