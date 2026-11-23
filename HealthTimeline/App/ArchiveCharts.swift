import Charts
import SwiftUI

enum ArchiveStyle {
    static let accent = Color(red: 0.05, green: 0.38, blue: 0.46)
    static let mint = Color(red: 0.48, green: 0.91, blue: 0.78)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let hero = LinearGradient(
        colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.06, green: 0.38, blue: 0.41)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

enum ArchiveFormat {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func measurement(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return "\(number(value, digits: digits)) \(unit)"
    }

    static func span(_ seconds: Double) -> String {
        let minutes = max(0, Int(min(seconds / 60, 1_000_000_000).rounded()))
        if minutes == 0, seconds > 0 { return "不到 1 分钟" }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    static func date(_ day: HealthDay) -> String {
        var style = Date.FormatStyle().year().month(.abbreviated).day()
        style.timeZone = HealthDay.calendar.timeZone
        return day.date.formatted(style)
    }

    static func hour(_ hour: Double) -> String {
        let minute = Int((hour * 60).rounded()) % 1_440
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct ReportCard<Content: View>: View {
    let title: String
    let caption: String?
    let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if let caption { Text(caption).font(.footnote).foregroundStyle(.secondary) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ArchiveStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct HeadlineStat: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

struct StatGrid: View {
    let stats: [HeadlineStat]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 143), spacing: 10)], spacing: 10) {
            ForEach(stats) { metric in
                VStack(alignment: .leading, spacing: 7) {
                    Text(metric.title).font(.footnote).foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .padding(13)
                .background(ArchiveStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ReportPoint: Identifiable {
    let day: HealthDay
    let value: Double
    var id: HealthDay { day }
}

struct RankValue: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

struct HourValue: Identifiable {
    let hour: Int
    let value: Double
    var id: Int { hour }
}

@MainActor
final class ReportSelection<Value>: ObservableObject {
    @Published var value: Value?
}

struct TrendCard: View {
    let title: String
    let points: [ReportPoint]
    let unit: String
    var totals = false
    var bars = false
    @StateObject private var selection = ReportSelection<Date>()
    private var selected: Date? { selection.value }

    var body: some View {
        let series = compactSeries
        ReportCard(title, caption: bucketDays > 1 ? "每 \(bucketDays) 天\(totals ? "汇总" : "平均")" : nil) {
            if let closest = selected.flatMap({ value in
                series.min { abs($0.day.date.timeIntervalSince(value)) < abs($1.day.date.timeIntervalSince(value)) }
            }) {
                Text("\(ArchiveFormat.date(closest.day)) · \(ArchiveFormat.measurement(closest.value, unit: unit, digits: 2))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(series) { point in
                    if bars {
                        BarMark(x: .value("日期", point.day.date, unit: .day), y: .value(title, point.value))
                            .foregroundStyle(ArchiveStyle.accent.gradient)
                    } else if series.count == 1 {
                        PointMark(x: .value("日期", point.day.date), y: .value(title, point.value))
                            .foregroundStyle(ArchiveStyle.accent)
                    } else {
                        LineMark(x: .value("日期", point.day.date), y: .value(title, point.value))
                            .foregroundStyle(ArchiveStyle.accent)
                    }
                }
                if let selected {
                    RuleMark(x: .value("选中日期", selected))
                        .foregroundStyle(.secondary.opacity(0.42))
                }
            }
            .chartXSelection(value: $selection.value)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 178)
            .accessibilityLabel(title)
        }
    }

    private var compactSeries: [ReportPoint] {
        guard bucketDays > 1 else { return points }
        let first = points.first?.day.ordinal ?? 0
        let buckets = Dictionary(grouping: points) { ($0.day.ordinal - first) / bucketDays }
        return buckets.keys.sorted().compactMap { key in
            guard let points = buckets[key], let first = points.first else { return nil }
            let sum = points.reduce(0) { $0 + $1.value }
            return ReportPoint(day: first.day, value: totals ? sum : sum / Double(points.count))
        }
    }

    private var bucketDays: Int {
        guard points.count > 150, let first = points.first?.day.ordinal, let last = points.last?.day.ordinal else { return 1 }
        return max(7, (last - first + 120) / 120)
    }
}

struct HourCard: View {
    let title: String
    let points: [HourValue]
    let unit: String

    var body: some View {
        ReportCard(title, caption: unit) {
            Chart(points) { point in
                BarMark(x: .value("时段", Double(point.hour) + 0.5), y: .value(title, point.value), width: .ratio(0.85))
                    .foregroundStyle(ArchiveStyle.accent.gradient)
            }
            .chartXScale(domain: 0.0...24.0)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24].map(Double.init)) { value in
                    AxisGridLine()
                    if let hour = value.as(Double.self) { AxisValueLabel { Text("\(Int(hour)):00") } }
                }
            }
            .frame(height: 145)
            .accessibilityLabel(title)
        }
    }
}

struct RankCard: View {
    let title: String
    let values: [RankValue]
    let unit: String
    var caption: String?

    var body: some View {
        ReportCard(title, caption: caption) {
            Chart(Array(values.prefix(10))) { point in
                BarMark(x: .value(unit, point.value), y: .value("项目", point.name))
                    .foregroundStyle(ArchiveStyle.accent.gradient)
            }
            .chartXAxisLabel(unit)
            .frame(height: CGFloat(max(110, min(10, values.count) * 30 + 38)))
            .accessibilityLabel(title)
        }
    }
}

struct MetricTrends: View {
    let slice: HealthSlice
    let metrics: [HealthMetric]

    var body: some View {
        ForEach(metrics) { metric in
            let points = slice.points(metric)
            if !points.isEmpty {
                TrendCard(title: metric.title, points: points, unit: metric.unit, totals: metric.isTotal, bars: metric.isTotal)
            }
        }
    }
}

struct EmptySection: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(ArchiveStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct HealthCalendar: View {
    let title: String
    let points: [ReportPoint]
    let unit: String
    @StateObject private var yearSelection = ReportSelection<Int>()

    var body: some View {
        if let year = activeYear {
            let visible = points.filter { HealthDay.calendar.component(.year, from: $0.day.date) == year }
            let intensity = visible.map(\.value).max() ?? 0
            ReportCard(title) {
                HStack {
                    Text("\(visible.count) 天 · \(unit)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(years.reversed(), id: \.self) { year in
                            Button(String(year)) { yearSelection.value = year }
                        }
                    } label: {
                        Label(String(year), systemImage: "calendar").font(.subheadline.weight(.semibold))
                    }
                }
                Chart(visible) { point in
                    let slot = cell(point.day, year: year)
                    let shade = intensity > 0 ? min(1, max(0, point.value / intensity)) : 0
                    RectangleMark(x: .value("周", slot.week), y: .value("星期", slot.weekday),
                                  width: .ratio(0.83), height: .ratio(0.83))
                        .foregroundStyle(ArchiveStyle.accent.opacity(0.15 + shade * 0.85))
                        .accessibilityLabel(ArchiveFormat.date(point.day))
                        .accessibilityValue(ArchiveFormat.measurement(point.value, unit: unit))
                }
                .chartXScale(domain: -0.5...53.5)
                .chartYScale(domain: -0.5...6.5)
                .chartXAxis {
                    AxisMarks(values: [0.0, 13.0, 26.0, 39.0]) { value in
                        if let week = value.as(Double.self) { AxisValueLabel { Text("\(Int(week) / 13 * 3 + 1) 月") } }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 95)
            }
        }
    }

    private var years: [Int] {
        Set(points.map { HealthDay.calendar.component(.year, from: $0.day.date) }).sorted()
    }

    private var activeYear: Int? {
        if let chosenYear = yearSelection.value, years.contains(chosenYear) { return chosenYear }
        return years.last
    }

    private func cell(_ day: HealthDay, year: Int) -> (week: Double, weekday: Double) {
        let calendar = HealthDay.calendar
        let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? day.date
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        let weekday = (calendar.component(.weekday, from: day.date) + 5) % 7
        return (Double((day.ordinal - HealthDay(date: first).ordinal + offset) / 7), Double(6 - weekday))
    }
}

extension HealthSlice {
    func points(_ metric: HealthMetric) -> [ReportPoint] {
        days.compactMap { entry in
            guard let value = entry.data.metrics[metric]?.value(for: metric) else { return nil }
            return ReportPoint(day: entry.day, value: value)
        }
    }

    func hours(_ metric: HealthMetric) -> [HourValue] {
        (byHour[metric] ?? [:]).sorted(by: { $0.key < $1.key }).compactMap { hour, stats in
            guard let value = stats.value(for: metric) else { return nil }
            return HourValue(hour: hour, value: value)
        }
    }
}
