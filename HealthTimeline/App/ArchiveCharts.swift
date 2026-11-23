import Charts
import SwiftUI

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

    static func shortDate(_ day: HealthDay) -> String {
        let calendar = HealthDay.calendar
        return "\(calendar.component(.month, from: day.date))/\(calendar.component(.day, from: day.date))"
    }

    static func month(_ day: HealthDay, includeYear: Bool = false) -> String {
        let calendar = HealthDay.calendar
        let month = calendar.component(.month, from: day.date)
        return includeYear ? "\(calendar.component(.year, from: day.date))年\(month)月" : "\(month)月"
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .archivePanel()
    }
}

struct HeadlineStat: Identifiable {
    let title: String
    let value: String
    var symbol: String? = nil
    var tint = ArchiveStyle.accent
    var id: String { title }
}

struct StatGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stats: [HeadlineStat]

    var body: some View {
        let column = dynamicTypeSize.isAccessibilitySize ? GridItem(.flexible()) : GridItem(.adaptive(minimum: 154), spacing: 12)
        LazyVGrid(columns: [column], alignment: .leading, spacing: 12) {
            ForEach(stats) { metric in
                VStack(alignment: .leading, spacing: 7) {
                    if let symbol = metric.symbol {
                        Image(systemName: symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(metric.tint)
                            .frame(width: 32, height: 32)
                            .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                    }
                    Text(metric.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(14)
                .archivePanel(cornerRadius: 22)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ReportPoint: Identifiable, Equatable {
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

private struct TrendInterval: Identifiable {
    let start: HealthDay
    let end: HealthDay
    let value: Double

    var id: HealthDay { start }
    var duration: TimeInterval { end.date.timeIntervalSince(start.date) }
    var center: Date { start.date.addingTimeInterval(duration / 2) }
}

struct TrendCard: View {
    let title: String
    let points: [ReportPoint]
    let unit: String
    var totals = false
    var bars = false
    var period: Calendar.Component = .day
    var showsClockTime = false
    var tint = ArchiveStyle.accent
    @StateObject private var selection = ReportSelection<Date>()

    var body: some View {
        let days = bucketDays
        let series = intervals(bucketDays: days)
        if let first = series.first, let last = series.last {
            let selected = selection.value.flatMap { value in
                series.min { abs($0.center.timeIntervalSince(value)) < abs($1.center.timeIntervalSince(value)) }
            }
            ReportCard(title, caption: days > 1 ? "每 \(days) 天\(totals ? "汇总" : "平均")" : nil) {
                Text(selected.map { detail($0, bucketDays: days) } ?? unit)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(series) { point in
                        if bars {
                            let inset = point.duration * 0.12
                            RectangleMark(xStart: .value("开始", point.start.date.addingTimeInterval(inset)),
                                          xEnd: .value("结束", point.end.date.addingTimeInterval(-inset)),
                                          yStart: .value(title, min(0, point.value)),
                                          yEnd: .value(title, max(0, point.value)))
                                .foregroundStyle(tint)
                                .accessibilityLabel(periodLabel(point, bucketDays: days))
                                .accessibilityValue(valueLabel(point.value))
                        } else if series.count == 1 {
                            PointMark(x: .value("日期", point.center), y: .value(title, point.value))
                                .foregroundStyle(tint)
                        } else {
                            LineMark(x: .value("日期", point.center), y: .value(title, point.value))
                                .foregroundStyle(tint)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("选中日期", selected.center))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                .chartXScale(domain: first.start.date...last.end.date)
                .chartYScale(domain: .automatic(includesZero: bars))
                .chartGesture { proxy in
                    SpatialTapGesture().onEnded { tap in
                        selection.value = proxy.value(atX: tap.location.x, as: Date.self)
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: axisDates(series)) { value in
                        AxisGridLine()
                        if let date = value.as(Date.self) {
                            let day = HealthDay(date: date)
                            AxisValueLabel(centered: false, anchor: horizontalLabelAnchor(value), offsetsMarks: false) {
                                Text(period == .month ? ArchiveFormat.month(day) : ArchiveFormat.shortDate(day))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartYAxis {
                    if showsClockTime {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            if let hour = value.as(Double.self) { AxisValueLabel { Text(ArchiveFormat.hour(hour)) } }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                }
                .frame(height: 178)
                .accessibilityLabel(title)
            }
            .onChange(of: points) { selection.value = nil }
        }
    }

    private func valueLabel(_ value: Double) -> String {
        showsClockTime ? ArchiveFormat.hour(value) : ArchiveFormat.measurement(value, unit: unit, digits: 2)
    }

    private func periodLabel(_ point: TrendInterval, bucketDays: Int) -> String {
        if bucketDays > 1, point.end > point.start.adding(1) {
            return "\(ArchiveFormat.date(point.start)) – \(ArchiveFormat.date(point.end.adding(-1)))"
        }
        return period == .month ? ArchiveFormat.month(point.start, includeYear: true) : ArchiveFormat.date(point.start)
    }

    private func detail(_ point: TrendInterval, bucketDays: Int) -> String {
        "\(periodLabel(point, bucketDays: bucketDays)) · \(valueLabel(point.value))"
    }

    private func axisDates(_ series: [TrendInterval]) -> [Date] {
        guard series.count > 4, let first = series.first, let last = series.last else { return series.map(\.center) }
        if period == .month { return (0...3).map { series[(series.count - 1) * $0 / 3].center } }
        let span = last.start.ordinal - first.start.ordinal
        return (0...3).map { index in
            first.start.adding(span * index / 3).date.addingTimeInterval(43_200)
        }
    }

    private func intervals(bucketDays: Int) -> [TrendInterval] {
        if bucketDays == 1 {
            return points.map { point in
                let end = period == .month ? HealthDay.calendar.dateInterval(of: .month, for: point.day.date)
                    .map { HealthDay(date: $0.end) } : nil
                return TrendInterval(start: point.day, end: end ?? point.day.adding(1), value: point.value)
            }
        }
        guard let first = points.first?.day, let last = points.last?.day else { return [] }
        let buckets = Dictionary(grouping: points) { ($0.day.ordinal - first.ordinal) / bucketDays }
        return buckets.keys.sorted().compactMap { key in
            guard let points = buckets[key] else { return nil }
            let start = first.adding(key * bucketDays)
            let sum = points.reduce(0) { $0 + $1.value }
            return TrendInterval(start: start, end: min(start.adding(bucketDays), last.adding(1)),
                                 value: totals ? sum : sum / Double(points.count))
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
    var tint = ArchiveStyle.accent

    var body: some View {
        let fill = LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .top, endPoint: .bottom)
        ReportCard(title, caption: unit) {
            Chart(points) { point in
                let hour = Double(point.hour)
                RectangleMark(xStart: .value("时段", hour + 0.08), xEnd: .value("时段", hour + 0.92),
                              yStart: .value(title, min(0, point.value)), yEnd: .value(title, max(0, point.value)))
                    .cornerRadius(2)
                    .foregroundStyle(fill)
                    .accessibilityLabel("\(ArchiveFormat.hour(hour)) 时段")
                    .accessibilityValue(ArchiveFormat.measurement(point.value, unit: unit))
            }
            .chartXScale(domain: 0.0...24.0)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: [0, 6, 12, 18, 24].map(Double.init)) { value in
                    AxisGridLine()
                    if let hour = value.as(Double.self) {
                        AxisValueLabel(centered: false, anchor: horizontalLabelAnchor(value), offsetsMarks: false) {
                            Text(hour == 24 ? "24:00" : ArchiveFormat.hour(hour)).font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 152)
            .padding(.horizontal, 5)
            .accessibilityLabel(title)
        }
    }
}

private func horizontalLabelAnchor(_ value: AxisValue) -> UnitPoint {
    if value.count > 1 {
        if value.index == 0 { return .topLeading }
        if value.index == value.count - 1 { return .topTrailing }
    }
    return .top
}

struct RankCard: View {
    let title: String
    let values: [RankValue]
    let unit: String
    var caption: String?

    var body: some View {
        let displayed = values.prefix(10)
        let maximum = displayed.map(\.value).max() ?? 0
        ReportCard(title, caption: caption) {
            ForEach(displayed) { point in
                VStack(alignment: .leading, spacing: 6) {
                    ReportValueRow(name: point.name, value: ArchiveFormat.measurement(point.value, unit: unit))
                    GeometryReader { geometry in
                        let fraction = maximum > 0 ? point.value / maximum : 0
                        Capsule().fill(ArchiveStyle.accent)
                            .frame(width: geometry.size.width * fraction)
                    }
                    .frame(height: 6)
                    .background(ArchiveStyle.accent.opacity(0.12), in: Capsule())
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

struct ReportValueRow: View {
    let name: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name).fixedSize()
                Spacer(minLength: 0)
                Text(value).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).fixedSize(horizontal: false, vertical: true)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
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
            .archivePanel()
    }
}

struct HealthCalendar: View {
    let title: String
    let points: [ReportPoint]
    let unit: String
    @StateObject private var yearSelection = ReportSelection<Int>()

    var body: some View {
        let calendar = HealthDay.calendar
        if let year = activeYear,
           let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let last = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) {
            let yearStart = HealthDay(date: first)
            let lastWeek = cell(HealthDay(date: last), yearStart: yearStart).week
            let quarters = [1, 4, 7, 10].compactMap { month -> Double? in
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
                return cell(HealthDay(date: date), yearStart: yearStart).week
            }
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
                    let slot = cell(point.day, yearStart: yearStart)
                    let shade = intensity > 0 ? min(1, max(0, point.value / intensity)) : 0
                    RectangleMark(xStart: .value("周", slot.week - 0.41), xEnd: .value("周", slot.week + 0.41),
                                  yStart: .value("星期", slot.weekday - 0.41), yEnd: .value("星期", slot.weekday + 0.41))
                        .foregroundStyle(ArchiveStyle.accent.opacity(0.15 + shade * 0.85))
                        .accessibilityLabel(ArchiveFormat.date(point.day))
                        .accessibilityValue(ArchiveFormat.measurement(point.value, unit: unit))
                }
                .chartXScale(domain: -0.5...(lastWeek + 0.5))
                .chartYScale(domain: -0.5...6.5)
                .chartXAxis {
                    AxisMarks(values: quarters) { value in
                        AxisValueLabel(centered: false, anchor: .leading) { Text("\(value.index * 3 + 1) 月") }
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

    private func cell(_ day: HealthDay, yearStart: HealthDay) -> (week: Double, weekday: Double) {
        let calendar = HealthDay.calendar
        let offset = (calendar.component(.weekday, from: yearStart.date) + 5) % 7
        let weekday = (calendar.component(.weekday, from: day.date) + 5) % 7
        return (Double((day.ordinal - yearStart.ordinal + offset) / 7), Double(6 - weekday))
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
