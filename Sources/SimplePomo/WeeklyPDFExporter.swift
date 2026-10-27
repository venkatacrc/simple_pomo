import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds a printable summary PDF for a week, month, quarter, or year —
/// then opens the standard macOS save panel.
@MainActor
enum WeeklyPDFExporter {

    /// Convenience: export the calendar week that contains `date`.
    static func export(store: DataStore, weekContaining date: Date = Date()) {
        export(store: store, period: .week, containing: date)
    }

    /// Export a PDF covering the `period` that contains `date`
    /// (e.g. `.month` → that calendar month, `.quarter` → that quarter).
    static func export(store: DataStore, period: ReportPeriod, containing date: Date = Date()) {
        let range = dateRange(for: period, containing: date)
        let data = renderPDF(store: store, period: period, range: range)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(period: period, range: range)
        panel.title = "Export \(period.label.lowercased()) summary"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                NSWorkspace.shared.open(url)
            } catch {
                NSLog("SimplePomo: PDF export failed: \(error)")
            }
        }
    }

    // MARK: - Date ranges (mirrors ReportsView)

    static func dateRange(for period: ReportPeriod, containing date: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        switch period {
        case .day:
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
            return start...end
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 7, to: start)!.addingTimeInterval(-1)
            return start...end
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let end = cal.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-1)
            return start...end
        case .quarter:
            return WalmartFiscal(now: date).currentQuarterRange
        case .year:
            return WalmartFiscal(now: date).currentFiscalYearRange
        }
    }

    static func periodLabel(for period: ReportPeriod, containing date: Date) -> String {
        let range = dateRange(for: period, containing: date)
        let start = range.lowerBound
        let cal = Calendar.current
        let fiscal = WalmartFiscal(now: date)
        switch period {
        case .day:
            return start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        case .week:
            let week = cal.component(.weekOfYear, from: start)
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            let endDay = cal.date(byAdding: .day, value: 6, to: start) ?? start
            return "Week \(week): \(start.formatted(fmt)) – \(endDay.formatted(fmt))"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .quarter:
            return fiscal.currentLongLabel
        case .year:
            return "FY\(fiscal.fiscalYear)"
        }
    }

    private static func defaultFilename(period: ReportPeriod, range: ClosedRange<Date>) -> String {
        let start = range.lowerBound
        let fiscal = WalmartFiscal(now: start)
        let fmt = DateFormatter()
        switch period {
        case .day:
            fmt.dateFormat = "yyyy-MM-dd"
            return "SimplePomo-Day-\(fmt.string(from: start)).pdf"
        case .week:
            fmt.dateFormat = "yyyy-'W'ww"
            return "SimplePomo-\(fmt.string(from: start)).pdf"
        case .month:
            fmt.dateFormat = "yyyy-MM"
            return "SimplePomo-Month-\(fmt.string(from: start)).pdf"
        case .quarter:
            return "SimplePomo-\(fiscal.currentLabel).pdf"
        case .year:
            return "SimplePomo-FY\(fiscal.fiscalYear).pdf"
        }
    }

    // MARK: - Layout

    private static let pageWidth: CGFloat = 612   // US Letter
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48

    private static func renderPDF(store: DataStore, period: ReportPeriod, range: ClosedRange<Date>) -> Data {
        let mutable = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: mutable as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        ctx.beginPage(mediaBox: &mediaBox)
        var y = pageHeight - margin
        y = drawTitle(ctx, y: y, period: period, range: range)
        y = drawSummary(ctx, y: y, store: store, period: period, range: range)
        y = drawSection(ctx, title: "Planned vs completed", y: y)
        y = drawComparison(ctx, y: y, store: store, range: range, mediaBox: &mediaBox)
        y = ensureSpace(ctx, y: y, needed: 80, mediaBox: &mediaBox)
        y = drawSection(ctx, title: "Focus sessions & notes", y: y)
        y = drawSessions(ctx, y: y, store: store, period: period, range: range, mediaBox: &mediaBox)
        ctx.endPage()
        ctx.closePDF()
        return mutable as Data
    }

    @discardableResult
    private static func ensureSpace(_ ctx: CGContext, y: CGFloat, needed: CGFloat,
                                    mediaBox: inout CGRect) -> CGFloat {
        if y < margin + needed {
            ctx.endPage()
            ctx.beginPage(mediaBox: &mediaBox)
            return pageHeight - margin
        }
        return y
    }

    // MARK: - Drawing helpers

    @discardableResult
    private static func drawTitle(_ ctx: CGContext, y: CGFloat,
                                  period: ReportPeriod, range: ClosedRange<Date>) -> CGFloat {
        let df = DateFormatter()
        df.dateStyle = .medium
        let start = range.lowerBound
        let endDay: Date = {
            switch period {
            case .week:
                return Calendar.current.date(byAdding: .day, value: 6, to: start) ?? range.upperBound
            default:
                return Calendar.current.startOfDay(for: range.upperBound)
            }
        }()
        let span: String
        switch period {
        case .day:
            span = df.string(from: start)
        case .week, .month, .quarter:
            span = "\(df.string(from: start)) – \(df.string(from: endDay))"
        case .year:
            span = "\(Calendar.current.component(.year, from: start))"
        }
        let line = "\(period.label) Summary  ·  \(span)"
        return drawText(ctx, line, at: CGPoint(x: margin, y: y),
                        font: .boldSystemFont(ofSize: 18), color: .black) - 8
    }

    @discardableResult
    private static func drawSummary(_ ctx: CGContext, y: CGFloat, store: DataStore,
                                    period: ReportPeriod, range: ClosedRange<Date>) -> CGFloat {
        let sessions = store.sessions.filter {
            $0.phase == .focus && $0.startedAt >= range.lowerBound && $0.startedAt <= range.upperBound
        }
        let minutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }
        let planned = store.plannedTasks(in: range)
        let done = planned.filter { task in
            task.isCompleted || store.focusSessionCount(for: task, in: range) >= max(task.estimatedPomodoros, 1)
        }.count
        let distinct = Set(sessions.map(\.taskTitle)).count
        let line = "\(sessions.count) pomodoros  ·  \(formatMinutes(minutes)) focus  ·  \(distinct) tasks  ·  \(done)/\(planned.count) planned done  ·  \(period.label.lowercased())"
        return drawText(ctx, line, at: CGPoint(x: margin, y: y),
                        font: .systemFont(ofSize: 11), color: .darkGray) - 16
    }

    @discardableResult
    private static func drawSection(_ ctx: CGContext, title: String, y: CGFloat) -> CGFloat {
        var next = drawText(ctx, title, at: CGPoint(x: margin, y: y),
                            font: .boldSystemFont(ofSize: 13), color: .black) - 4
        ctx.setStrokeColor(NSColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: next + 10))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: next + 10))
        ctx.strokePath()
        next -= 6
        return next
    }

    @discardableResult
    private static func drawComparison(_ ctx: CGContext, y: CGFloat, store: DataStore,
                                       range: ClosedRange<Date>,
                                       mediaBox: inout CGRect) -> CGFloat {
        var cursor = y
        let planned = store.plannedTasks(in: range)
        if planned.isEmpty {
            return drawText(ctx, "No tasks were planned in this period.",
                            at: CGPoint(x: margin, y: cursor),
                            font: .systemFont(ofSize: 10), color: .gray) - 10
        }

        cursor = drawText(ctx, pad("Task", 34) + "  " + pad("Plan", 6, right: true) + "  " +
                               pad("Done", 6, right: true) + "  " + pad("Time", 8, right: true) + "  Status",
                          at: CGPoint(x: margin, y: cursor),
                          font: .monospacedSystemFont(ofSize: 9, weight: .semibold),
                          color: .darkGray) - 2

        for task in planned {
            cursor = ensureSpace(ctx, y: cursor, needed: 36, mediaBox: &mediaBox)
            let sessions = store.focusSessionCount(for: task, in: range)
            let minutes = store.focusMinutes(for: task, in: range)
            let status: String
            if task.isCompleted || sessions >= max(task.estimatedPomodoros, 1) {
                status = "Done"
            } else if sessions > 0 {
                status = "Partial"
            } else {
                status = "Missed"
            }
            let line = pad(task.title, 34) + "  " +
                       pad("\(task.estimatedPomodoros)", 6, right: true) + "  " +
                       pad("\(sessions)", 6, right: true) + "  " +
                       pad(formatMinutes(minutes), 8, right: true) + "  " + status
            cursor = drawText(ctx, line, at: CGPoint(x: margin, y: cursor),
                              font: .monospacedSystemFont(ofSize: 9, weight: .regular),
                              color: .black) - 1
            let log = task.notesLog
            if !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for noteLine in log.components(separatedBy: "\n").prefix(4) {
                    cursor = ensureSpace(ctx, y: cursor, needed: 20, mediaBox: &mediaBox)
                    cursor = drawText(ctx, String(("    " + noteLine).prefix(95)),
                                      at: CGPoint(x: margin, y: cursor),
                                      font: .systemFont(ofSize: 8), color: .gray) - 1
                }
            }
        }
        return cursor - 12
    }

    @discardableResult
    private static func drawSessions(_ ctx: CGContext, y: CGFloat, store: DataStore,
                                     period: ReportPeriod, range: ClosedRange<Date>,
                                     mediaBox: inout CGRect) -> CGFloat {
        var cursor = y
        let cal = Calendar.current
        let sessions = store.sessions
            .filter { $0.phase == .focus && $0.startedAt >= range.lowerBound && $0.startedAt <= range.upperBound }
            .sorted { $0.startedAt > $1.startedAt }

        if sessions.isEmpty {
            return drawText(ctx, "No focus sessions in this period.",
                            at: CGPoint(x: margin, y: cursor),
                            font: .systemFont(ofSize: 10), color: .gray) - 10
        }

        // For year/quarter, group by month; otherwise by day.
        let groupByMonth = (period == .year || period == .quarter)
        let byBucket = Dictionary(grouping: sessions) { session -> Date in
            if groupByMonth {
                let comps = cal.dateComponents([.year, .month], from: session.startedAt)
                return cal.date(from: comps) ?? cal.startOfDay(for: session.startedAt)
            }
            return cal.startOfDay(for: session.startedAt)
        }
        let buckets = byBucket.keys.sorted(by: >)
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE, MMM d"
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM yyyy"

        for bucket in buckets {
            cursor = ensureSpace(ctx, y: cursor, needed: 48, mediaBox: &mediaBox)
            let header = groupByMonth ? monthFmt.string(from: bucket) : dayFmt.string(from: bucket)
            cursor = drawText(ctx, header,
                              at: CGPoint(x: margin, y: cursor),
                              font: .boldSystemFont(ofSize: 10), color: .black) - 2
            let bucketSessions = byBucket[bucket] ?? []
            let grouped = Dictionary(grouping: bucketSessions, by: \.taskTitle)
            for (title, items) in grouped.sorted(by: { $0.key < $1.key }) {
                cursor = ensureSpace(ctx, y: cursor, needed: 28, mediaBox: &mediaBox)
                let mins = items.reduce(0.0) { $0 + $1.durationMinutes }
                let line = "  • \(title)  —  \(items.count)×  ·  \(formatMinutes(mins))"
                cursor = drawText(ctx, String(line.prefix(95)),
                                  at: CGPoint(x: margin, y: cursor),
                                  font: .systemFont(ofSize: 9), color: .black) - 1

                if let task = store.tasks.first(where: {
                    $0.title.caseInsensitiveCompare(title) == .orderedSame &&
                    !$0.notesLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) {
                    let italic = NSFontManager.shared.convert(
                        .systemFont(ofSize: 8), toHaveTrait: .italicFontMask
                    )
                    // For longer periods, show only the last few note lines.
                    let noteLines = task.notesLog.components(separatedBy: "\n")
                    let shown = groupByMonth ? Array(noteLines.suffix(3)) : noteLines
                    for noteLine in shown {
                        cursor = ensureSpace(ctx, y: cursor, needed: 18, mediaBox: &mediaBox)
                        cursor = drawText(ctx, String(("      " + noteLine).prefix(95)),
                                          at: CGPoint(x: margin, y: cursor),
                                          font: italic, color: .darkGray) - 1
                    }
                }
            }
            cursor -= 6
        }
        return cursor
    }

    /// Draws text with AppKit fonts and returns the y position below the line.
    private static func drawText(_ ctx: CGContext,
                                 _ string: String,
                                 at point: CGPoint,
                                 font: NSFont,
                                 color: NSColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attr = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: point.x, y: point.y - bounds.height)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return point.y - bounds.height - 4
    }

    private static func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
        let clipped = String(text.prefix(width))
        let padCount = max(0, width - clipped.count)
        let spaces = String(repeating: " ", count: padCount)
        return right ? spaces + clipped : clipped + spaces
    }
}
