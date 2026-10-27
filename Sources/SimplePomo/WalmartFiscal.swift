import Foundation

/// Walmart fiscal calendar: year runs Feb 1 → Jan 31 and is named by the
/// calendar year in which it *ends* (FY2027 = Feb 1, 2026 – Jan 31, 2027).
///
/// | Quarter | Months              | Ends       |
/// |---------|---------------------|------------|
/// | Q1      | February – April    | April 30   |
/// | Q2      | May – July          | July 31    |
/// | Q3      | August – October    | October 31 |
/// | Q4      | November – January  | January 31 |
struct WalmartFiscal {
    let now: Date

    /// 1…4
    let quarter: Int
    /// Fiscal year label, e.g. 2027 for FY2027
    let fiscalYear: Int
    /// Inclusive start of the current quarter (00:00)
    let quarterStart: Date
    /// Inclusive end of the current quarter (last second of last day)
    let quarterEnd: Date
    /// First day of the next quarter
    let nextQuarterStart: Date
    let nextQuarter: Int
    let nextFiscalYear: Int

    init(now: Date = Date()) {
        self.now = now
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: now)
        let y = cal.component(.year, from: today)
        let m = cal.component(.month, from: today)

        // FY is named by the year it ends (Jan 31). Jan belongs to the FY of
        // that calendar year; Feb–Dec belong to FY = calendar year + 1.
        let fy = (m == 1) ? y : y + 1
        self.fiscalYear = fy

        let q: Int
        switch m {
        case 2, 3, 4:    q = 1
        case 5, 6, 7:    q = 2
        case 8, 9, 10:   q = 3
        default:         q = 4   // Nov, Dec, Jan
        }
        self.quarter = q

        let bounds = Self.quarterBounds(quarter: q, fiscalYear: fy, calendar: cal)
        self.quarterStart = bounds.start
        self.quarterEnd = bounds.end

        let nextQ = q == 4 ? 1 : q + 1
        let nextFY = q == 4 ? fy + 1 : fy
        self.nextQuarter = nextQ
        self.nextFiscalYear = nextFY
        self.nextQuarterStart = Self.quarterBounds(quarter: nextQ, fiscalYear: nextFY, calendar: cal).start
    }

    /// Short label like "Q3FY27".
    var currentLabel: String { "Q\(quarter)FY\(fiscalYear % 100)" }

    /// Short label for the upcoming quarter, e.g. "Q4FY27".
    var nextLabel: String { "Q\(nextQuarter)FY\(nextFiscalYear % 100)" }

    /// Long label like "Q3 FY2027".
    var currentLongLabel: String { "Q\(quarter) FY\(fiscalYear)" }

    /// Days remaining in the current quarter (includes today as remaining).
    /// Oct 27 → Oct 31 = 5 days remaining (27,28,29,30,31).
    var daysRemainingInQuarter: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endDay = cal.startOfDay(for: quarterEnd)
        let days = cal.dateComponents([.day], from: today, to: endDay).day ?? 0
        return max(0, days + 1)
    }

    /// Days until the next quarter begins (0 if today is the first day of a quarter).
    /// Oct 27 → Nov 1 = 5 days.
    var daysUntilNextQuarter: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let next = cal.startOfDay(for: nextQuarterStart)
        return max(0, cal.dateComponents([.day], from: today, to: next).day ?? 0)
    }

    /// Closed date range for the current Walmart quarter (for Reports/PDF).
    var currentQuarterRange: ClosedRange<Date> { quarterStart...quarterEnd }

    /// Closed date range for the current Walmart fiscal year.
    var currentFiscalYearRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: fiscalYear - 1, month: 2, day: 1))!
        let endDay = cal.date(from: DateComponents(year: fiscalYear, month: 1, day: 31))!
        let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
        return start...end
    }

    /// A representative date inside the previous Walmart quarter.
    var dateInPreviousQuarter: Date {
        let prevQ = quarter == 1 ? 4 : quarter - 1
        let prevFY = quarter == 1 ? fiscalYear - 1 : fiscalYear
        return Self.quarterBounds(quarter: prevQ, fiscalYear: prevFY).start
    }

    /// A representative date inside the previous Walmart fiscal year.
    var dateInPreviousFiscalYear: Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: fiscalYear - 2, month: 2, day: 1))
            ?? now
    }

    /// Start/end for a given Walmart quarter in a fiscal year.
    static func quarterBounds(quarter: Int, fiscalYear: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        // Q1 starts Feb 1 of (FY-1); Q4 ends Jan 31 of FY.
        let startComps: DateComponents
        let endComps: DateComponents
        switch quarter {
        case 1:
            startComps = DateComponents(year: fiscalYear - 1, month: 2, day: 1)
            endComps = DateComponents(year: fiscalYear - 1, month: 4, day: 30)
        case 2:
            startComps = DateComponents(year: fiscalYear - 1, month: 5, day: 1)
            endComps = DateComponents(year: fiscalYear - 1, month: 7, day: 31)
        case 3:
            startComps = DateComponents(year: fiscalYear - 1, month: 8, day: 1)
            endComps = DateComponents(year: fiscalYear - 1, month: 10, day: 31)
        default: // 4
            startComps = DateComponents(year: fiscalYear - 1, month: 11, day: 1)
            endComps = DateComponents(year: fiscalYear, month: 1, day: 31)
        }
        let start = calendar.date(from: startComps) ?? Date()
        let endDay = calendar.date(from: endComps) ?? start
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
        return (start, end)
    }
}
