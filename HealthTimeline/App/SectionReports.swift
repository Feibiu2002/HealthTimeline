import Charts
import SwiftUI

struct SectionReports: View {
    let section: ArchiveSection
    let report: HealthReport
    let slice: HealthSlice
    let navigate: (ArchiveSection) -> Void

    var body: some View {
        switch section {
        case .overview: OverviewReport(slice: slice, navigate: navigate)
        case .hearing: HearingReport(slice: slice)
        case .heart: HeartReport(slice: slice)
        case .sleep: SleepReport(slice: slice)
        case .activity: ActivityReport(slice: slice)
        case .energy: EnergyReport(slice: slice)
        case .mobility: MobilityReport(slice: slice)
        case .devices: DevicesReport(report: report)
        }
    }
}

private struct OverviewReport: View {
    let slice: HealthSlice
    let navigate: (ArchiveSection) -> Void

    private var nights: [SleepNight] { slice.days.compactMap(\.data.sleep).filter { $0.sleepSeconds > 0 } }

    var body: some View {
        Button {
            navigate(.hearing)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("耳机聆听时长", systemImage: "headphones")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(ArchiveStyle.mint)
                Text(slice.listening.total.seconds > 0 ? ArchiveFormat.span(Double(slice.listening.total.seconds)) : "当前范围没有耳机记录")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Label("查看耳机明细", systemImage: "arrow.right").font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .foregroundStyle(.white)
            .background(ArchiveStyle.hero, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)

        StatGrid(stats: [
            HeadlineStat(title: "有记录的日期", value: "\(slice.days.count.formatted()) 天"),
            metricStat(slice, .steps),
            metricStat(slice, .heartRate, label: "平均心率"),
            HeadlineStat(title: "平均每日睡眠", value: averageSleep),
            metricStat(slice, .activeEnergy),
            metricStat(slice, .walkingDistance)
        ])

        if !slice.hours(.heartRate).isEmpty {
            HourCard(title: "一天中的平均心率", points: slice.hours(.heartRate), unit: "bpm")
        }
        let activeHours = slice.hours(.activeEnergy)
        if !activeHours.isEmpty {
            HourCard(title: "一天中的活动能量", points: activeHours, unit: "kcal")
        }
        let dailySleep = slice.days.compactMap { entry -> ReportPoint? in
            guard let hours = entry.data.sleep?.sleepSeconds, hours > 0 else { return nil }
            return ReportPoint(day: entry.day, value: Double(hours) / 3_600)
        }
        if !dailySleep.isEmpty {
            TrendCard(title: "每日睡眠趋势", points: dailySleep, unit: "小时")
        }
        MetricTrends(slice: slice, metrics: [.weight, .height, .water, .caffeine, .mindfulness, .sexualActivity])
        if slice.days.isEmpty {
            EmptySection(text: "这个日期范围没有健康记录。", icon: "calendar")
        }
        PeakCard(title: "这段时间的峰值", values: [
            peak(slice.points(.steps), label: "步数最多", unit: "步"),
            peak(slice.points(.activeEnergy), label: "活动能量最高", unit: "kcal"),
            peak(dailySleep, label: "睡眠最长", unit: "小时")
        ].compactMap { $0 })
    }

    private var averageSleep: String {
        guard !nights.isEmpty else { return "—" }
        return ArchiveFormat.span(Double(nights.reduce(0) { $0 + $1.sleepSeconds }) / Double(nights.count))
    }
}

private struct HearingReport: View {
    let slice: HealthSlice
    @StateObject private var deviceSelection = ReportSelection<String>()

    private var chosen: String? { deviceSelection.value }

    private var name: String? {
        chosen.flatMap { slice.listening.byDevice[$0] == nil ? nil : $0 }
    }

    private var rankedDevices: [(key: String, value: ListeningTotals)] {
        slice.listening.byDevice.sorted {
            $0.value.seconds == $1.value.seconds ? $0.key < $1.key : $0.value.seconds > $1.value.seconds
        }
    }

    private func totals(_ day: ListeningDay) -> ListeningTotals {
        guard let name else { return day.total }
        return day.byDevice[name] ?? ListeningTotals()
    }

    var body: some View {
        if rankedDevices.isEmpty {
            EmptySection(text: "当前日期范围没有耳机音量记录。", icon: "headphones")
        } else {
            deviceFilter
            let total = totals(slice.listening)
            let daily: [ReportPoint] = slice.days.compactMap { entry in
                let value = totals(entry.data.listening)
                return value.seconds > 0 ? ReportPoint(day: entry.day, value: value.hours) : nil
            }
            StatGrid(stats: [
                HeadlineStat(title: "累计聆听", value: ArchiveFormat.span(Double(total.seconds))),
                HeadlineStat(title: "有聆听记录", value: "\(daily.count.formatted()) 天"),
                HeadlineStat(title: "平均音量", value: ArchiveFormat.measurement(total.average, unit: "dBA")),
                HeadlineStat(title: "≥ 80 dBA 时长占比", value: total.loudShare?.formatted(.percent.precision(.fractionLength(0...1))) ?? "—")
            ])
            TrendCard(title: "每日聆听时长", points: daily, unit: "小时", totals: true, bars: true)
            let hours = name.flatMap { slice.listening.deviceHours[$0] } ?? slice.listening.byHour
            let volume = hours.sorted { $0.key < $1.key }.compactMap { hour, data in
                data.average.map { HourValue(hour: hour, value: $0) }
            }
            if !volume.isEmpty { HourCard(title: "各时段平均音量", points: volume, unit: "dBA") }
            ReportCard("各耳机聆听时长") {
                ForEach(rankedDevices, id: \.key) { row in
                    Button {
                        deviceSelection.value = chosen == row.key ? nil : row.key
                    } label: {
                        HStack {
                            Image(systemName: chosen == row.key ? "checkmark.circle.fill" : "headphones")
                                .foregroundStyle(ArchiveStyle.accent)
                            Text(row.key).foregroundStyle(.primary)
                            Spacer()
                            Text(ArchiveFormat.span(Double(row.value.seconds)))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen == row.key ? .isSelected : [])
                }
            }
            PeakCard(title: "聆听记录", values: [
                peak(daily, label: "聆听最久的一天", unit: "小时"),
                total.peak.map { HeadlineStat(title: "最高记录音量", value: ArchiveFormat.measurement($0, unit: "dBA")) }
            ].compactMap { $0 })
            Text("时长来自「健康」记录的耳机音量样本。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var deviceFilter: some View {
        Menu {
            Button("全部耳机") { deviceSelection.value = nil }
            ForEach(rankedDevices, id: \.key) { device in
                Button(device.key) { deviceSelection.value = device.key }
            }
        } label: {
            HStack {
                Label(name ?? "全部耳机", systemImage: "headphones")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .padding(14)
            .background(ArchiveStyle.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct HeartReport: View {
    let slice: HealthSlice

    private let metrics: [HealthMetric] = [
        .heartRate, .restingHeartRate, .hrv, .oxygen, .respiratoryRate, .vo2, .heartRecovery, .afib
    ]

    private var events: [HealthDayEntry] {
        slice.days.filter { $0.data.events.contains { $0.title != "耳机音量通知" } }
    }

    var body: some View {
        let available = metrics.filter { slice.value($0) != nil }
        if available.isEmpty && events.isEmpty {
            EmptySection(text: "当前日期范围没有心脏和呼吸记录。", icon: "heart")
        } else {
            StatGrid(stats: available.prefix(6).map { metricStat(slice, $0) })
            let hourly = slice.hours(.heartRate)
            if !hourly.isEmpty { HourCard(title: "24 小时心率", points: hourly, unit: "bpm") }
            WeekHeart(slice: slice)
            if !slice.heartHistogram.isEmpty {
                ReportCard("心率分布", caption: "每格 5 bpm") {
                    Chart(slice.heartHistogram.sorted(by: { $0.key < $1.key }), id: \.key) { bin in
                        RectangleMark(xStart: .value("bpm", Double(bin.key) + 0.25),
                                      xEnd: .value("bpm", Double(bin.key) + 4.75),
                                      yStart: .value("采样数", 0), yEnd: .value("采样数", bin.value))
                            .foregroundStyle(ArchiveStyle.accent)
                            .accessibilityLabel("\(bin.key) 至 \(bin.key + 5) bpm")
                            .accessibilityValue("\(bin.value.formatted()) 条")
                    }
                    .chartXAxisLabel("bpm")
                    .frame(height: 150)
                }
            }
            MetricTrends(slice: slice, metrics: available)
            let heartDays = slice.points(.heartRate)
            if !heartDays.isEmpty { HealthCalendar(title: "心率日历", points: heartDays, unit: "bpm") }
            if let extremes = slice.metrics[.heartRate], extremes.count > 0 {
                PeakCard(title: "心率记录", values: [
                    HeadlineStat(title: "最低采样", value: ArchiveFormat.measurement(extremes.min, unit: "bpm")),
                    HeadlineStat(title: "最高采样", value: ArchiveFormat.measurement(extremes.max, unit: "bpm"))
                ])
            }
            if !events.isEmpty {
                ReportCard("心率通知与症状记录") {
                    ForEach(events.suffix(12).reversed()) { day in
                        Text("\(ArchiveFormat.date(day.day)) · \(day.data.events.filter { $0.title != "耳机音量通知" }.map(\.title).joined(separator: "、"))")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct WeekHeart: View {
    let slice: HealthSlice

    var body: some View {
        let values = weekdayMeans
        if !values.isEmpty { RankCard(title: "一周中的平均心率", values: values, unit: "bpm") }
    }

    private var weekdayMeans: [RankValue] {
        let labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        var days: [Int: SampleStats] = [:]
        for entry in slice.days {
            guard let stats = entry.data.metrics[.heartRate] else { continue }
            let weekday = HealthDay.calendar.component(.weekday, from: entry.day.date)
            days[weekday, default: .init()].merge(stats)
        }
        return [2, 3, 4, 5, 6, 7, 1].compactMap { day in
            days[day]?.mean.map { RankValue(name: labels[day - 1], value: $0) }
        }
    }
}

private struct NightEntry: Identifiable {
    let day: HealthDay
    let sleep: SleepNight
    var id: HealthDay { day }
}

private struct SleepReport: View {
    let slice: HealthSlice

    private var nights: [NightEntry] {
        slice.days.compactMap { entry in entry.data.sleep.map { NightEntry(day: entry.day, sleep: $0) } }
            .filter { $0.sleep.sleepSeconds > 0 }
    }

    var body: some View {
        let rows = nights
        if rows.isEmpty && slice.value(.wristTemperature) == nil && slice.value(.sleepGoal) == nil && slice.value(.breathingDisturbances) == nil {
            EmptySection(text: "当前日期范围没有睡眠记录。", icon: "moon.stars")
        } else {
            if !rows.isEmpty {
                let sum = rows.reduce(0) { $0 + $1.sleep.sleepSeconds }
                StatGrid(stats: [
                    HeadlineStat(title: "睡眠记录日", value: "\(rows.count.formatted()) 天"),
                    HeadlineStat(title: "平均每日", value: ArchiveFormat.span(Double(sum) / Double(rows.count)))
                ])
                SleepTimeline(rows: Array(rows.suffix(14)))
                let points = rows.map { ReportPoint(day: $0.day, value: Double($0.sleep.sleepSeconds) / 3_600) }
                TrendCard(title: "每日睡眠时长", points: points, unit: "小时", bars: true)
                SleepStageCard(rows: rows)
                let drift = monthlyBedtimes(rows)
                if !drift.isEmpty {
                    TrendCard(title: "每月平均入睡时间", points: drift, unit: "主要睡眠时段", period: .month, showsClockTime: true)
                }
                PeakCard(title: "睡眠记录", values: [peak(points, label: "最长睡眠", unit: "小时")].compactMap { $0 })
            }
            MetricTrends(slice: slice, metrics: [.sleepGoal, .wristTemperature, .breathingDisturbances])
        }
    }

    private func monthlyBedtimes(_ nights: [NightEntry]) -> [ReportPoint] {
        let months = Dictionary(grouping: nights) { month($0.day) }
        return months.keys.sorted().compactMap { day in
            guard let starts = months[day]?.compactMap(\.sleep.primaryStartHour), !starts.isEmpty else { return nil }
            return ReportPoint(day: day, value: starts.reduce(0, +) / Double(starts.count))
        }
    }
}

private struct SleepTimeline: View {
    let rows: [NightEntry]
    @ScaledMetric(relativeTo: .caption) private var dateWidth: CGFloat = 45
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 23
    @ScaledMetric(relativeTo: .caption2) private var tickWidth: CGFloat = 36

    private let hours = [12, 18, 24, 30, 36]

    var body: some View {
        ReportCard("睡眠时间轴", caption: "最近 \(rows.count) 个记录日 · 当天中午至次日中午") {
            VStack(spacing: 0) {
                timeAxis
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(ArchiveFormat.shortDate(row.day))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: dateWidth, alignment: .trailing)
                        plot(row.sleep.intervals)
                    }
                    .frame(height: rowHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ArchiveFormat.date(row.day))
                    .accessibilityValue(accessibleIntervals(row.sleep))
                }
            }
        }
    }

    private var timeAxis: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: dateWidth)
            GeometryReader { geometry in
                let width = geometry.size.width
                let innerHours = width >= 6 * tickWidth ? [18, 24, 30] : width >= 3 * tickWidth ? [24] : []
                ZStack {
                    HStack {
                        tick(12)
                        Spacer(minLength: 0)
                        tick(36)
                    }
                    ForEach(innerHours, id: \.self) { hour in
                        tick(hour).position(x: width * CGFloat(hour - 12) / 24, y: geometry.size.height / 2)
                    }
                }
                .frame(height: geometry.size.height)
            }
        }
        .frame(height: rowHeight)
        .accessibilityHidden(true)
    }

    private func tick(_ hour: Int) -> some View {
        Text(ArchiveFormat.hour(Double(hour)))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func plot(_ intervals: [Range<Int>]) -> some View {
        Canvas { context, size in
            var grid = Path()
            for hour in hours {
                let x = size.width * CGFloat(hour - 12) / 24
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            grid.move(to: CGPoint(x: 0, y: size.height - 0.25))
            grid.addLine(to: CGPoint(x: size.width, y: size.height - 0.25))
            context.stroke(grid, with: .color(Color(uiColor: .separator)), lineWidth: 0.5)

            let scale = size.width / CGFloat(SleepNight.timeline.count)
            let height = size.height * 0.35
            for interval in intervals {
                let rect = CGRect(x: CGFloat(interval.lowerBound - SleepNight.timeline.lowerBound) * scale,
                                  y: (size.height - height) / 2, width: CGFloat(interval.count) * scale, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2)), with: .color(ArchiveStyle.accent))
            }
        }
    }

    private func accessibleIntervals(_ night: SleepNight) -> String {
        let times = night.intervals.map { interval in
            let start = ArchiveFormat.hour(Double(interval.lowerBound) / 3_600)
            let end = ArchiveFormat.hour(Double(interval.upperBound) / 3_600)
            return "\(start) 到 \(end)"
        }
        return ([ArchiveFormat.span(Double(night.sleepSeconds))] + times).joined(separator: "，")
    }
}

private struct SleepStageCard: View {
    let rows: [NightEntry]

    var body: some View {
        let stages = SleepStage.allCases.filter(\.asleep).compactMap { stage -> RankValue? in
            let seconds = rows.reduce(0) { $0 + ($1.sleep.stages[stage] ?? 0) }
            return seconds > 0 ? RankValue(name: stage.title, value: Double(seconds) / 3_600) : nil
        }
        if !stages.isEmpty {
            ReportCard("睡眠结构", caption: "所选日期内的累计小时") {
                Chart(stages) { stage in
                    SectorMark(angle: .value("时长", stage.value), innerRadius: .ratio(0.57), angularInset: 1.5)
                        .foregroundStyle(by: .value("阶段", stage.name))
                }
                .chartForegroundStyleScale(range: [ArchiveStyle.accent, .indigo, .teal, .gray])
                .frame(height: 180)
            }
        }
    }
}

private struct ActivityReport: View {
    let slice: HealthSlice

    var body: some View {
        let stepDays = slice.points(.steps)
        let rings = slice.days.compactMap(\.data.rings)
        if stepDays.isEmpty && slice.workouts.isEmpty && rings.isEmpty && slice.value(.walkingDistance) == nil &&
            slice.value(.exercise) == nil && slice.value(.daylight) == nil && slice.value(.standTime) == nil &&
            slice.value(.cycling) == nil {
            EmptySection(text: "当前日期范围没有活动记录。", icon: "figure.walk")
        } else {
            StatGrid(stats: [
                metricStat(slice, .steps), metricStat(slice, .walkingDistance), metricStat(slice, .exercise),
                HeadlineStat(title: "体能训练", value: "\(slice.workouts.count.formatted()) 次")
            ])
            if !stepDays.isEmpty { HealthCalendar(title: "步数日历", points: stepDays, unit: "步") }
            MetricTrends(slice: slice, metrics: [.steps, .walkingDistance, .exercise, .daylight, .standTime, .cycling])
            if !rings.isEmpty {
                RankCard(title: "活动圆环达标天数", values: [
                    RankValue(name: "活动", value: Double(rings.filter { $0.moveGoal > 0 && $0.move >= $0.moveGoal }.count)),
                    RankValue(name: "锻炼", value: Double(rings.filter { $0.exerciseGoal > 0 && $0.exercise >= $0.exerciseGoal }.count)),
                    RankValue(name: "站立", value: Double(rings.filter { $0.standGoal > 0 && $0.stand >= $0.standGoal }.count)),
                    RankValue(name: "全部合上", value: Double(rings.filter(\.closedAll).count))
                ], unit: "天", caption: "\(rings.count.formatted()) 天有活动摘要")
            }
            if !slice.workouts.isEmpty { WorkoutCards(workouts: slice.workouts) }
            PeakCard(title: "活动记录", values: [
                peak(stepDays, label: "步数最多", unit: "步"),
                peak(slice.points(.walkingDistance), label: "走跑最远", unit: "km")
            ].compactMap { $0 })
        }
    }
}

private struct WorkoutCards: View {
    let workouts: [Workout]

    var body: some View {
        RankCard(title: "训练类型", values: typeRanks, unit: "次")
        HourCard(title: "通常什么时候训练", points: hourCounts, unit: "次")
        RankCard(title: "每周训练分布", values: weekdayRanks, unit: "次")
        ReportCard("最近训练") {
            let recent = Array(workouts.sorted { $0.time.second > $1.time.second }.prefix(20))
            ForEach(recent.indices, id: \.self) { index in
                let item = recent[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(item.kind)).font(.subheadline.weight(.semibold))
                    Text(detail(item)).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var typeRanks: [RankValue] {
        var counts: [String: Int] = [:]
        for workout in workouts { counts[label(workout.kind), default: 0] += 1 }
        let values: [RankValue] = counts.map { name, count in
            RankValue(name: name, value: Double(count))
        }
        return values.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.name < rhs.name }
            return lhs.value > rhs.value
        }
    }

    private var hourCounts: [HourValue] {
        var counts: [Int: Int] = [:]
        for workout in workouts { counts[workout.time.hour, default: 0] += 1 }
        return counts.keys.sorted().map { hour in
            HourValue(hour: hour, value: Double(counts[hour, default: 0]))
        }
    }

    private var weekdayRanks: [RankValue] {
        let groups = Dictionary(grouping: workouts) { HealthDay.calendar.component(.weekday, from: $0.time.day.date) }
        let labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return [2, 3, 4, 5, 6, 7, 1].map { weekday in
            RankValue(name: labels[weekday - 1], value: Double(groups[weekday]?.count ?? 0))
        }
    }

    private func detail(_ workout: Workout) -> String {
        var fields = [ArchiveFormat.date(workout.time.day), ArchiveFormat.span(workout.minutes * 60)]
        if let distance = workout.kilometers { fields.append(ArchiveFormat.measurement(distance, unit: "km")) }
        if let energy = workout.kilocalories { fields.append(ArchiveFormat.measurement(energy, unit: "kcal")) }
        if let heart = workout.averageHeartRate { fields.append(ArchiveFormat.measurement(heart, unit: "bpm")) }
        return fields.joined(separator: " · ")
    }

    private func label(_ type: String) -> String {
        [
            "Walking": "步行", "Running": "跑步", "Cycling": "骑行", "Swimming": "游泳",
            "Hiking": "徒步", "TraditionalStrengthTraining": "传统力量训练",
            "FunctionalStrengthTraining": "功能性力量训练", "Elliptical": "椭圆机",
            "CoreTraining": "核心训练", "Yoga": "瑜伽", "Dance": "舞蹈",
            "HighIntensityIntervalTraining": "高强度间歇训练", "Other": "其他"
        ][type] ?? type
    }
}

private struct EnergyReport: View {
    let slice: HealthSlice
    private let metrics: [HealthMetric] = [.activeEnergy, .basalEnergy, .effort, .flights, .environment]

    var body: some View {
        let available = metrics.filter { slice.value($0) != nil }
        if available.isEmpty && slice.standingHours == 0 && slice.idleHours == 0 {
            EmptySection(text: "当前日期范围没有能量和站立记录。", icon: "bolt")
        } else {
            StatGrid(stats: available.map { metricStat(slice, $0) })
            let effort = slice.hours(.effort)
            if !effort.isEmpty { HourCard(title: "各时段身体负荷", points: effort, unit: HealthMetric.effort.unit) }
            let composition = [HealthMetric.basalEnergy, .activeEnergy].compactMap { metric in
                slice.value(metric).map { RankValue(name: metric.title, value: $0) }
            }
            if !composition.isEmpty { RankCard(title: "静息与活动能量", values: composition, unit: "kcal") }
            MetricTrends(slice: slice, metrics: available.filter { $0 != .flights })
            let flights = slice.points(.flights)
            if !flights.isEmpty {
                TrendCard(title: "每月爬楼层数", points: monthlyTotals(flights), unit: "层", totals: true, bars: true, period: .month)
            }
            if slice.standingHours > 0 || slice.idleHours > 0 {
                RankCard(title: "站立小时", values: [
                    RankValue(name: "已站立", value: Double(slice.standingHours)),
                    RankValue(name: "未站立", value: Double(slice.idleHours))
                ], unit: "小时")
            }
            PeakCard(title: "能量记录", values: [
                peak(slice.points(.activeEnergy), label: "活动能量最高", unit: "kcal"),
                peak(flights, label: "爬楼最多", unit: "层")
            ].compactMap { $0 })
        }
    }
}

private struct MobilityReport: View {
    let slice: HealthSlice
    private let metrics: [HealthMetric] = [
        .walkingSpeed, .stepLength, .doubleSupport, .asymmetry, .stairAscent, .stairDescent,
        .walkingHeartRate, .steadiness, .sixMinuteWalk
    ]

    var body: some View {
        let available = metrics.filter { slice.value($0) != nil }
        if available.isEmpty {
            EmptySection(text: "当前日期范围没有步态或移动能力记录。", icon: "figure.walk")
        } else {
            StatGrid(stats: available.prefix(6).map { metricStat(slice, $0) })
            MetricTrends(slice: slice, metrics: available)
            PeakCard(title: "移动记录", values: [
                peak(slice.points(.walkingSpeed), label: "步行速度最高", unit: "m/s"),
                peak(slice.points(.sixMinuteWalk), label: "六分钟步行最远", unit: "m")
            ].compactMap { $0 })
        }
    }
}

private struct DevicesReport: View {
    let report: HealthReport

    var body: some View {
        StatGrid(stats: [
            HeadlineStat(title: "写入来源", value: "\(report.sources.count.formatted()) 个"),
            HeadlineStat(title: "设备名称", value: "\(report.devices.count.formatted()) 个"),
            HeadlineStat(title: "导出中的记录", value: report.recordCount.formatted())
        ])
        if !report.devices.isEmpty { RankCard(title: "设备", values: ranked(report.devices), unit: "条", caption: "全部导出记录") }
        if !report.sources.isEmpty { RankCard(title: "数据来源", values: ranked(report.sources), unit: "条", caption: "全部导出记录") }
        if !report.profile.isEmpty {
            ReportCard("导出文件中的个人资料") {
                ForEach(report.profile.keys.sorted(), id: \.self) { label in
                    LabeledContent(label, value: profileValue(report.profile[label] ?? ""))
                        .font(.subheadline)
                }
            }
        }
        if !report.types.isEmpty {
            ReportCard("记录种类", caption: report.exported.map { "导出于 \(ArchiveFormat.date($0))" }) {
                DisclosureGroup("查看全部 \(report.types.count) 类") {
                    ForEach(ranked(report.types)) { record in
                        LabeledContent(recordLabel(record.name), value: ArchiveFormat.number(record.value, digits: 0))
                            .font(.footnote)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func ranked(_ names: [String: Int]) -> [RankValue] {
        names.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { RankValue(name: $0.key, value: Double($0.value)) }
    }

    private func profileValue(_ raw: String) -> String {
        ["Male": "男性", "Female": "女性", "Other": "其他"][raw] ?? raw
    }

    private func recordLabel(_ type: String) -> String {
        let name = type.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
        if name == "HeadphoneAudioExposure" { return "耳机音量" }
        if name == "SleepAnalysis" { return "睡眠分析" }
        if name == "ActivitySummary" { return "活动摘要" }
        return HealthMetric(rawValue: name)?.title ?? name
    }
}

private struct PeakCard: View {
    let title: String
    let values: [HeadlineStat]

    var body: some View {
        if !values.isEmpty {
            ReportCard(title) {
                ForEach(values) { value in
                    ReportValueRow(name: value.title, value: value.value)
                }
            }
        }
    }
}

private func metricStat(_ slice: HealthSlice, _ metric: HealthMetric, label: String? = nil) -> HeadlineStat {
    HeadlineStat(title: label ?? metric.title, value: ArchiveFormat.measurement(slice.value(metric), unit: metric.unit))
}

private func peak(_ points: [ReportPoint], label: String, unit: String) -> HeadlineStat? {
    points.max { $0.value < $1.value }.map {
        HeadlineStat(title: label, value: "\(ArchiveFormat.date($0.day)) · \(ArchiveFormat.measurement($0.value, unit: unit))")
    }
}

private func month(_ day: HealthDay) -> HealthDay {
    let date = HealthDay.calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
    return HealthDay(date: date)
}

private func monthlyTotals(_ series: [ReportPoint]) -> [ReportPoint] {
    let groups = Dictionary(grouping: series) { month($0.day) }
    return groups.keys.sorted().map { key in
        ReportPoint(day: key, value: (groups[key] ?? []).reduce(0) { $0 + $1.value })
    }
}
