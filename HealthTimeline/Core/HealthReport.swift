import Foundation

struct HealthDay: Hashable, Comparable, Identifiable, Sendable {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    let ordinal: Int
    var id: Int { ordinal }
    var date: Date { Date(timeIntervalSince1970: Double(ordinal) * 86_400) }

    init(ordinal: Int) {
        self.ordinal = ordinal
    }

    init(date: Date) {
        self.init(ordinal: Int(floor(date.timeIntervalSince1970 / 86_400)))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    func adding(_ days: Int) -> Self {
        Self(ordinal: ordinal + days)
    }
}

struct HealthTime: Sendable {
    let day: HealthDay
    let secondOfDay: Int
    let offset: Int

    var hour: Int { secondOfDay / 3_600 }
    var localSecond: Int { day.ordinal * 86_400 + secondOfDay }
    var second: Int { localSecond - offset }
}

struct HealthTimeReader {
    private var days: [String: HealthDay] = [:]

    mutating func day(_ text: String) -> HealthDay? {
        let key = String(text.prefix(10))
        if let cached = days[key] { return cached }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, parts.count == 3, (1900...9999).contains(parts[0]),
              let date = HealthDay.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        let components = HealthDay.calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == parts[0], components.month == parts[1], components.day == parts[2] else {
            return nil
        }
        let result = HealthDay(date: date)
        days[key] = result
        return result
    }

    mutating func time(_ text: String?) -> HealthTime? {
        guard let text, let date = day(text) else { return nil }
        let bytes = Array(text.utf8)
        guard bytes.count >= 19, bytes[10] == 32 || bytes[10] == 84,
              bytes[13] == 58, bytes[16] == 58,
              let hour = pair(bytes, 11), hour < 24,
              let minute = pair(bytes, 14), minute < 60,
              let second = pair(bytes, 17), second < 60 else { return nil }

        let suffix = bytes[19...]
        var offset = 0
        if let zone = suffix.firstIndex(where: { $0 == 43 || $0 == 45 }) {
            guard let zoneHour = pair(bytes, zone + 1), zoneHour <= 23 else { return nil }
            let minuteIndex = zone + 3 < bytes.count && bytes[zone + 3] == 58 ? zone + 4 : zone + 3
            guard let zoneMinute = pair(bytes, minuteIndex), zoneMinute < 60 else { return nil }
            offset = (zoneHour * 60 + zoneMinute) * (bytes[zone] == 45 ? -60 : 60)
        }
        return HealthTime(day: date, secondOfDay: (hour * 60 + minute) * 60 + second, offset: offset)
    }

    private func pair(_ bytes: [UInt8], _ index: Int) -> Int? {
        guard index + 1 < bytes.count, (48...57).contains(bytes[index]), (48...57).contains(bytes[index + 1]) else {
            return nil
        }
        return Int(bytes[index] - 48) * 10 + Int(bytes[index + 1] - 48)
    }
}

enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case heartRate = "HeartRate", restingHeartRate = "RestingHeartRate", hrv = "HeartRateVariabilitySDNN"
    case oxygen = "OxygenSaturation", respiratoryRate = "RespiratoryRate", vo2 = "VO2Max"
    case heartRecovery = "HeartRateRecoveryOneMinute", afib = "AtrialFibrillationBurden"
    case steps = "StepCount", walkingDistance = "DistanceWalkingRunning", cycling = "DistanceCycling"
    case activeEnergy = "ActiveEnergyBurned", basalEnergy = "BasalEnergyBurned", effort = "PhysicalEffort"
    case flights = "FlightsClimbed", standTime = "AppleStandTime", exercise = "AppleExerciseTime"
    case daylight = "TimeInDaylight", environment = "EnvironmentalAudioExposure"
    case weight = "BodyMass", height = "Height", water = "DietaryWater", caffeine = "DietaryCaffeine"
    case walkingSpeed = "WalkingSpeed", stepLength = "WalkingStepLength"
    case doubleSupport = "WalkingDoubleSupportPercentage", asymmetry = "WalkingAsymmetryPercentage"
    case stairAscent = "StairAscentSpeed", stairDescent = "StairDescentSpeed"
    case walkingHeartRate = "WalkingHeartRateAverage", steadiness = "AppleWalkingSteadiness"
    case sixMinuteWalk = "SixMinuteWalkTestDistance"
    case breathingDisturbances = "AppleSleepingBreathingDisturbances"
    case wristTemperature = "AppleSleepingWristTemperature"
    case sleepGoal = "SleepDurationGoal", mindfulness = "MindfulSession"
    case sexualActivity = "SexualActivity"

    var id: Self { self }

    var title: String {
        switch self {
        case .heartRate: "心率"
        case .restingHeartRate: "静息心率"
        case .hrv: "心率变异性"
        case .oxygen: "血氧饱和度"
        case .respiratoryRate: "呼吸频率"
        case .vo2: "最大摄氧量"
        case .heartRecovery: "一分钟心率恢复"
        case .afib: "房颤负荷"
        case .steps: "步数"
        case .walkingDistance: "步行与跑步距离"
        case .cycling: "骑行距离"
        case .activeEnergy: "活动能量"
        case .basalEnergy: "静息能量"
        case .effort: "身体负荷"
        case .flights: "爬楼层数"
        case .standTime: "站立时间"
        case .exercise: "锻炼时间"
        case .daylight: "日光下时间"
        case .environment: "环境音量"
        case .weight: "体重"
        case .height: "身高"
        case .water: "饮水量"
        case .caffeine: "咖啡因"
        case .walkingSpeed: "步行速度"
        case .stepLength: "步长"
        case .doubleSupport: "双支撑时间占比"
        case .asymmetry: "步行不对称占比"
        case .stairAscent: "上楼速度"
        case .stairDescent: "下楼速度"
        case .walkingHeartRate: "步行平均心率"
        case .steadiness: "步行稳定性"
        case .sixMinuteWalk: "六分钟步行距离"
        case .breathingDisturbances: "睡眠呼吸扰动"
        case .wristTemperature: "睡眠手腕温度"
        case .sleepGoal: "睡眠目标"
        case .mindfulness: "正念练习"
        case .sexualActivity: "性行为记录"
        }
    }

    var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .heartRecovery, .walkingHeartRate: "bpm"
        case .hrv: "ms"
        case .oxygen, .afib, .doubleSupport, .asymmetry, .steadiness: "%"
        case .respiratoryRate: "次/分"
        case .vo2: "mL/kg/min"
        case .steps: "步"
        case .walkingDistance, .cycling: "km"
        case .activeEnergy, .basalEnergy: "kcal"
        case .effort: "kcal/kg/h"
        case .flights: "层"
        case .standTime, .exercise, .daylight, .sleepGoal, .mindfulness: "分钟"
        case .environment: "dBA"
        case .weight: "kg"
        case .height, .sixMinuteWalk: "m"
        case .water: "mL"
        case .caffeine: "mg"
        case .walkingSpeed, .stairAscent, .stairDescent: "m/s"
        case .stepLength: "cm"
        case .breathingDisturbances, .sexualActivity: "次"
        case .wristTemperature: "°C"
        }
    }

    var isTotal: Bool {
        switch self {
        case .steps, .walkingDistance, .cycling, .activeEnergy, .basalEnergy, .flights, .standTime,
             .exercise, .daylight, .water, .caffeine, .mindfulness, .sexualActivity: true
        default: false
        }
    }

    var recordsHours: Bool {
        self == .heartRate || self == .effort || self == .activeEnergy
    }

    func normalized(_ value: Double, unit source: String) -> Double {
        switch self {
        case .oxygen, .afib, .doubleSupport, .asymmetry, .steadiness:
            return abs(value) <= 1 ? value * 100 : value
        case .walkingDistance, .cycling:
            return HealthUnits.kilometers(value, unit: source)
        case .activeEnergy, .basalEnergy:
            return HealthUnits.kilocalories(value, unit: source)
        case .standTime, .exercise, .daylight, .sleepGoal:
            return HealthUnits.minutes(value, unit: source)
        case .weight:
            return source == "lb" ? value * 0.45359237 : value
        case .height, .stepLength, .sixMinuteWalk:
            let meters = HealthUnits.kilometers(value, unit: source.isEmpty ? unit : source) * 1_000
            return self == .stepLength ? meters * 100 : meters
        case .water:
            return source == "L" ? value * 1_000 : source == "fl oz (US)" ? value * 29.57353 : value
        case .caffeine:
            return source == "g" ? value * 1_000 : value
        case .wristTemperature:
            return source.uppercased().contains("F") ? (value - 32) * 5 / 9 : value
        case .walkingSpeed, .stairAscent, .stairDescent:
            return source == "km/hr" ? value / 3.6 : source == "mi/hr" ? value * 0.44704 : value
        default:
            return value
        }
    }
}

enum HealthUnits {
    static func kilometers(_ value: Double, unit: String) -> Double {
        switch unit {
        case "m": value / 1_000
        case "cm": value / 100_000
        case "mi": value * 1.609344
        case "yd": value * 0.0009144
        case "ft": value * 0.0003048
        case "in": value * 0.0000254
        default: value
        }
    }

    static func kilocalories(_ value: Double, unit: String) -> Double {
        switch unit {
        case "kJ": value / 4.184
        case "J": value / 4_184
        default: value
        }
    }

    static func minutes(_ value: Double, unit: String) -> Double {
        switch unit {
        case "s", "sec": value / 60
        case "h", "hr": value * 60
        default: value
        }
    }
}

struct SampleStats: Sendable {
    private(set) var count = 0
    private(set) var sum = 0.0
    private(set) var min = Double.infinity
    private(set) var max = -Double.infinity

    var mean: Double? { count > 0 ? sum / Double(count) : nil }

    mutating func add(_ value: Double) {
        count += 1
        sum += value
        min = Swift.min(min, value)
        max = Swift.max(max, value)
    }

    mutating func merge(_ other: SampleStats) {
        count += other.count
        sum += other.sum
        min = Swift.min(min, other.min)
        max = Swift.max(max, other.max)
    }

    func value(for metric: HealthMetric) -> Double? {
        metric.isTotal && count > 0 ? sum : mean
    }
}

struct ListeningTotals: Sendable {
    var seconds = 0
    var decibelSeconds = 0.0
    var loudSeconds = 0
    var peak: Double?

    var hours: Double { Double(seconds) / 3_600 }
    var average: Double? { seconds > 0 ? decibelSeconds / Double(seconds) : nil }
    var loudShare: Double? { seconds > 0 ? Double(loudSeconds) / Double(seconds) : nil }

    mutating func add(seconds length: Int, decibels: Double) {
        seconds += length
        decibelSeconds += Double(length) * decibels
        if decibels >= 80 { loudSeconds += length }
        peak = max(peak ?? decibels, decibels)
    }

    mutating func merge(_ other: ListeningTotals) {
        seconds += other.seconds
        decibelSeconds += other.decibelSeconds
        loudSeconds += other.loudSeconds
        if let maxValue = other.peak { peak = max(peak ?? maxValue, maxValue) }
    }
}

struct ListeningDay: Sendable {
    var byDevice: [String: ListeningTotals] = [:]
    var byHour: [Int: ListeningTotals] = [:]
    var deviceHours: [String: [Int: ListeningTotals]] = [:]
    var total = ListeningTotals()

    mutating func merge(_ other: ListeningDay) {
        total.merge(other.total)
        for (name, totals) in other.byDevice { byDevice[name, default: .init()].merge(totals) }
        for (hour, totals) in other.byHour { byHour[hour, default: .init()].merge(totals) }
        for (name, hours) in other.deviceHours {
            for (hour, totals) in hours { deviceHours[name, default: [:]][hour, default: .init()].merge(totals) }
        }
    }
}

enum SleepStage: String, CaseIterable, Sendable {
    case deep = "AsleepDeep", rem = "AsleepREM", core = "AsleepCore"
    case unspecified = "AsleepUnspecified", awake = "Awake", inBed = "InBed"

    init?(exportValue: String) {
        switch exportValue.replacingOccurrences(of: "HKCategoryValueSleepAnalysis", with: "") {
        case "0", "InBed": self = .inBed
        case "1", "Asleep", "AsleepUnspecified": self = .unspecified
        case "2", "Awake": self = .awake
        case "3", "AsleepCore": self = .core
        case "4", "AsleepDeep": self = .deep
        case "5", "AsleepREM": self = .rem
        default: return nil
        }
    }

    var asleep: Bool { self != .awake && self != .inBed }

    var title: String {
        switch self {
        case .deep: "深睡"
        case .rem: "快速眼动"
        case .core: "核心"
        case .unspecified: "未分阶段"
        case .awake: "清醒"
        case .inBed: "卧床"
        }
    }
}

struct SleepNight: Sendable {
    // Seconds since midnight of the report date, from noon through the next noon.
    static let timeline = 43_200..<129_600

    let intervals: [Range<Int>]
    let stages: [SleepStage: Int]

    var sleepSeconds: Int {
        stages.reduce(0) { $0 + ($1.key.asleep ? $1.value : 0) }
    }

    var primaryStartHour: Double? {
        guard let first = intervals.first else { return nil }
        var bestStart = first.lowerBound
        var bestDuration = first.count
        var sessionStart = first.lowerBound
        var sessionDuration = first.count
        var previousEnd = first.upperBound
        for interval in intervals.dropFirst() {
            // Keep brief awakenings within a session while separating naps from it.
            if interval.lowerBound - previousEnd > 3_600 {
                sessionStart = interval.lowerBound
                sessionDuration = 0
            }
            sessionDuration += interval.count
            previousEnd = interval.upperBound
            if sessionDuration > bestDuration {
                bestStart = sessionStart
                bestDuration = sessionDuration
            }
        }
        return Double(bestStart) / 3_600
    }
}

struct Workout: Sendable {
    let time: HealthTime
    let kind: String
    let minutes: Double
    var kilometers: Double?
    var kilocalories: Double?
    var averageHeartRate: Double?
}

struct ActivityRings: Sendable {
    let move: Double
    let moveGoal: Double
    let exercise: Double
    let exerciseGoal: Double
    let stand: Double
    let standGoal: Double

    var closedAll: Bool {
        moveGoal > 0 && exerciseGoal > 0 && standGoal > 0 &&
        move >= moveGoal && exercise >= exerciseGoal && stand >= standGoal
    }
}

struct HealthEvent: Sendable {
    let time: HealthTime
    let title: String
}

struct HealthDayData: Sendable {
    var metrics: [HealthMetric: SampleStats] = [:]
    var byHour: [HealthMetric: [Int: SampleStats]] = [:]
    var heartHistogram: [Int: Int] = [:]
    var listening = ListeningDay()
    var sleep: SleepNight?
    var rings: ActivityRings?
    var workouts: [Workout] = []
    var events: [HealthEvent] = []
    var standingHours = 0
    var idleHours = 0

    mutating func add(_ value: Double, metric: HealthMetric, hour: Int) {
        metrics[metric, default: .init()].add(value)
        if metric.recordsHours { byHour[metric, default: [:]][hour, default: .init()].add(value) }
        if metric == .heartRate, value >= 20, value <= 260 {
            heartHistogram[Int(value) / 5 * 5, default: 0] += 1
        }
    }
}

struct HealthDayEntry: Identifiable, Sendable {
    let day: HealthDay
    let data: HealthDayData
    var id: HealthDay { day }
}

struct HealthReport: Sendable {
    let exported: HealthDay?
    let days: [HealthDayEntry]
    let sources: [String: Int]
    let devices: [String: Int]
    let types: [String: Int]
    let profile: [String: String]

    var dates: ClosedRange<HealthDay>? {
        guard let first = days.first?.day, let last = days.last?.day else { return nil }
        return first...last
    }

    var recordCount: Int { types.values.reduce(0, +) }

    func select(_ dates: ClosedRange<HealthDay>?) -> HealthSlice {
        HealthSlice(days: days.filter { dates?.contains($0.day) ?? true })
    }
}

struct HealthSlice: Sendable {
    let days: [HealthDayEntry]
    var metrics: [HealthMetric: SampleStats] = [:]
    var byHour: [HealthMetric: [Int: SampleStats]] = [:]
    var heartHistogram: [Int: Int] = [:]
    var listening = ListeningDay()
    var workouts: [Workout] = []
    var standingHours = 0
    var idleHours = 0

    init(days: [HealthDayEntry]) {
        self.days = days
        for entry in days {
            let day = entry.data
            for (metric, stats) in day.metrics { metrics[metric, default: .init()].merge(stats) }
            for (metric, hours) in day.byHour {
                for (hour, stats) in hours { byHour[metric, default: [:]][hour, default: .init()].merge(stats) }
            }
            for (bin, count) in day.heartHistogram { heartHistogram[bin, default: 0] += count }
            listening.merge(day.listening)
            workouts.append(contentsOf: day.workouts)
            standingHours += day.standingHours
            idleHours += day.idleHours
        }
    }

    func value(_ metric: HealthMetric) -> Double? {
        metrics[metric]?.value(for: metric)
    }
}
