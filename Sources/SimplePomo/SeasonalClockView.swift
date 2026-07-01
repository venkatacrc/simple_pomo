import SwiftUI

// MARK: - Season colors

/// Seasonal palette anchored to the four cardinal moments of the year.
/// Inspired by Scott Thrift's *The Present* — a 365-day analog clock that
/// completes one revolution per year.
enum Season: String, CaseIterable {
    case winter, spring, summer, autumn

    /// The pure hue for this season's anchor point (equinox / solstice).
    var pureColor: Color {
        switch self {
        case .winter: return Color(red: 0.96, green: 0.98, blue: 1.00) // snowy white
        case .spring: return Color(red: 0.18, green: 0.75, blue: 0.30) // pure green
        case .summer: return Color(red: 1.00, green: 0.84, blue: 0.13) // pure yellow
        case .autumn: return Color(red: 0.86, green: 0.22, blue: 0.18) // pure red
        }
    }

    var label: String { rawValue.uppercased() }
}

// MARK: - Clock model

/// Snapshot of "where in the year we are". A full cycle is anchored to the
/// winter solstice (Dec 21) which lives at the top of the dial.
struct SeasonalClock {
    let now: Date

    private static let solsticeMonth = 12
    private static let solsticeDay = 21

    /// The most recent winter solstice before `now`.
    static func cycleStart(before date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let year = cal.component(.year, from: date)
        let thisWinter = cal.date(from: DateComponents(
            year: year, month: solsticeMonth, day: solsticeDay,
            hour: 0, minute: 0, second: 0)) ?? date
        if date >= thisWinter { return thisWinter }
        return cal.date(from: DateComponents(
            year: year - 1, month: solsticeMonth, day: solsticeDay,
            hour: 0, minute: 0, second: 0)) ?? date
    }

    static func cycleEnd(after date: Date) -> Date {
        let start = cycleStart(before: date)
        return Calendar.current.date(byAdding: .year, value: 1, to: start) ?? start
    }

    /// 0…1 progress through the annual cycle.
    var progress: Double {
        let start = Self.cycleStart(before: now)
        let end = Self.cycleEnd(after: now)
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(1, elapsed / total))
    }

    /// Rotation angle for the hand — 0° = top (winter), sweeping clockwise.
    var handAngle: Angle { .degrees(progress * 360) }

    /// Day number in the cycle (1-based).
    var cycleDay: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Self.cycleStart(before: now))
        let today = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return days + 1
    }

    /// Total days in the current cycle (365 or 366).
    var cycleLength: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Self.cycleStart(before: now))
        let end = cal.startOfDay(for: Self.cycleEnd(after: now))
        return cal.dateComponents([.day], from: start, to: end).day ?? 365
    }

    var currentSeason: Season {
        switch progress {
        case ..<0.25: return .winter
        case ..<0.5:  return .spring
        case ..<0.75: return .summer
        default:      return .autumn
        }
    }

    var nextSeason: Season {
        switch currentSeason {
        case .winter: return .spring
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        }
    }

    /// Days until the next equinox / solstice boundary.
    var daysUntilNextSeason: Int {
        let target: Double
        switch progress {
        case ..<0.25: target = 0.25
        case ..<0.5:  target = 0.5
        case ..<0.75: target = 0.75
        default:      target = 1.0
        }
        let start = Self.cycleStart(before: now)
        let end = Self.cycleEnd(after: now)
        let total = end.timeIntervalSince(start)
        let targetDate = start.addingTimeInterval(total * target)
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: now),
            to: cal.startOfDay(for: targetDate)
        ).day ?? 0
        return max(0, days)
    }
}

// MARK: - View

struct SeasonalClockView: View {
    /// The rendered diameter of the clock face.
    var diameter: CGFloat = 260

    var body: some View {
        // Refresh once per minute — the hand moves ~0.00068° per second on a
        // 365-day dial, so per-minute updates are more than smooth enough.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let model = SeasonalClock(now: context.date)
            VStack(spacing: 18) {
                header(model: model)
                clockFace(model: model)
                    .frame(width: diameter, height: diameter)
                footer(model: model)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    // MARK: - Header

    private func header(model: SeasonalClock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("The Present")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("A year at a glance")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "sun.max.fill")
                .foregroundStyle(model.currentSeason.pureColor)
                .font(.title3)
        }
    }

    // MARK: - Clock face

    private func clockFace(model: SeasonalClock) -> some View {
        ZStack {
            gradientRing
            innerDial
            ticks
            seasonLabels
            centerInfo(model: model)
            hand(model: model)
        }
    }

    private var gradientRing: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Season.winter.pureColor, location: 0.00),
                        .init(color: Season.spring.pureColor, location: 0.25),
                        .init(color: Season.summer.pureColor, location: 0.50),
                        .init(color: Season.autumn.pureColor, location: 0.75),
                        .init(color: Season.winter.pureColor, location: 1.00)
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                lineWidth: 22
            )
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    private var innerDial: some View {
        Circle()
            .inset(by: 22)
            .fill(
                RadialGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
    }

    /// 12 month ticks — one every 30°.
    private var ticks: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(i % 3 == 0 ? 0.9 : 0.35))
                        .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 10 : 6)
                        .offset(y: -(size / 2 - 30))
                        .rotationEffect(.degrees(Double(i) * 30))
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// Season labels floating just inside the outer ring at each cardinal.
    private var seasonLabels: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inset = size / 2 - 46
            ZStack {
                seasonLabel(.winter, at: CGPoint(x: 0, y: -inset))
                seasonLabel(.spring, at: CGPoint(x: inset, y: 0))
                seasonLabel(.summer, at: CGPoint(x: 0, y: inset))
                seasonLabel(.autumn, at: CGPoint(x: -inset, y: 0))
            }
            .frame(width: size, height: size)
        }
    }

    private func seasonLabel(_ season: Season, at point: CGPoint) -> some View {
        Text(season.label)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(season.pureColor)
            .shadow(color: .black.opacity(0.55), radius: 2)
            .offset(x: point.x, y: point.y)
    }

    private func centerInfo(model: SeasonalClock) -> some View {
        VStack(spacing: 2) {
            Text(model.currentSeason.label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(model.currentSeason.pureColor)
            Text(model.now, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("day \(model.cycleDay) / \(model.cycleLength)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// The hand — a slim capsule with a counterweight and pivot dot.
    private func hand(model: SeasonalClock) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let handLength = size / 2 - 30
            ZStack {
                // Main hand pointing up
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: handLength)
                    .offset(y: -handLength / 2)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                // Counterweight
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 3, height: 18)
                    .offset(y: 9)

                // Pivot dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            }
            .frame(width: size, height: size)
            .rotationEffect(model.handAngle)
            .animation(.easeInOut(duration: 0.6), value: model.progress)
        }
    }

    // MARK: - Footer

    private func footer(model: SeasonalClock) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.nextSeason.pureColor)
                        .frame(width: 8, height: 8)
                    Text(model.nextSeason.rawValue.capitalized)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("in")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(model.daysUntilNextSeason) day\(model.daysUntilNextSeason == 1 ? "" : "s")")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 6)
    }
}
