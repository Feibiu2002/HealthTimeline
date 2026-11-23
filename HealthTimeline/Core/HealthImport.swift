import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum HealthImportProgress: Sendable {
    case expanding(Double)
    case reading(Int)
    case calculating
}

enum HealthImport {
    static func read(_ source: URL, progress: @escaping (HealthImportProgress) -> Void) throws -> HealthReport {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()

        if source.pathExtension.lowercased() != "zip" {
            return try readXML(source, progress: progress)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let xml = folder.appendingPathComponent("health-export.xml")
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard FileManager.default.createFile(atPath: xml.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try HealthZip.unpack(source, to: xml) { progress(.expanding($0)) }
        return try readXML(xml, progress: progress)
    }

    private static func readXML(_ source: URL, progress: @escaping (HealthImportProgress) -> Void) throws -> HealthReport {
        guard let stream = InputStream(url: source) else { throw CocoaError(.fileReadUnknown) }
        progress(.reading(0))
        let collector = HealthXMLCollector(progress: progress)
        let parser = XMLParser(stream: stream)
        parser.delegate = collector
        parser.shouldResolveExternalEntities = false
        let complete = parser.parse()
        try Task.checkCancellation()
        guard complete, collector.sawHealthData else { throw HealthImportError.invalidXML }
        progress(.calculating)
        return try collector.report()
    }
}

private final class HealthXMLCollector: NSObject, XMLParserDelegate {
    private struct AudioSpan {
        let lower: Int
        let upper: Int
        let decibels: Double
    }

    private struct SleepSpan {
        let lower: Int
        let upper: Int
        let stage: SleepStage
    }

    private struct SleepEdge {
        let second: Int
        let stage: SleepStage
        let change: Int
    }

    private struct WorkoutBuilder {
        var workout: Workout
        var distance: Double?
        var energy: Double?
    }

    private static let eventNames = [
        "HighHeartRateEvent": "高心率通知", "LowHeartRateEvent": "低心率通知",
        "IrregularHeartRhythmEvent": "心律不齐通知", "RapidPoundingOrFlutteringHeartbeat": "心悸记录",
        "Fatigue": "疲劳记录", "ShortnessOfBreath": "气短记录", "Dizziness": "眩晕记录",
        "HeadphoneAudioExposureEvent": "耳机音量通知"
    ]

    private let progress: (HealthImportProgress) -> Void
    private var clock = HealthTimeReader()
    private var depth = 0
    private var elementCount = 0
    private var recordCount = 0
    private var exported: HealthDay?
    private var days: [HealthDay: HealthDayData] = [:]
    private var audio: [HealthDay: [String: [AudioSpan]]] = [:]
    private var sleep: [HealthDay: [SleepSpan]] = [:]
    private var sources: [String: Int] = [:]
    private var devices: [String: Int] = [:]
    private var deviceNames: [String: String] = [:]
    private var types: [String: Int] = [:]
    private var profile: [String: String] = [:]
    private var workout: WorkoutBuilder?
    private(set) var sawHealthData = false

    init(progress: @escaping (HealthImportProgress) -> Void) {
        self.progress = progress
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        depth += 1
        if depth == 1 {
            sawHealthData = elementName == "HealthData"
            if !sawHealthData { parser.abortParsing() }
            return
        }
        elementCount += 1
        if elementCount.isMultiple(of: 4_096), Task.isCancelled {
            parser.abortParsing()
            return
        }
        if elementCount.isMultiple(of: 32_768) { progress(.reading(recordCount)) }

        if depth == 3, elementName == "WorkoutStatistics" {
            addWorkoutStats(attributes)
        }
        guard depth == 2 else { return }
        switch elementName {
        case "Record": addRecord(attributes)
        case "Workout": startWorkout(attributes)
        case "ActivitySummary": addRings(attributes)
        case "Me": addProfile(attributes)
        case "ExportDate":
            if let value = attributes["value"] { exported = clock.day(value) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if depth == 2, elementName == "Workout", var entry = workout {
            entry.workout.kilometers = entry.distance ?? entry.workout.kilometers
            entry.workout.kilocalories = entry.energy ?? entry.workout.kilocalories
            days[entry.workout.time.day, default: .init()].workouts.append(entry.workout)
            workout = nil
        }
        depth -= 1
    }

    private func addRecord(_ fields: [String: String]) {
        guard let identifier = fields["type"] else { return }
        let type = Self.suffix(identifier)
        types[identifier, default: 0] += 1
        recordCount += 1
        let name = countSource(fields)
        guard let start = clock.time(fields["startDate"]) else { return }
        if days[start.day] == nil { days[start.day] = .init() }

        let value = fields["value"] ?? ""
        switch type {
        case "HeadphoneAudioExposure":
            guard let db = number(value), let end = clock.time(fields["endDate"]), end.second > start.second else { return }
            addListening(from: start, to: end, decibels: db, device: name)
        case "SleepAnalysis":
            guard let stage = SleepStage(exportValue: value), let end = clock.time(fields["endDate"]),
                  end.second > start.second else { return }
            addSleep(from: start, to: end, stage: stage)
        case "AppleStandHour":
            if value.hasSuffix("Stood") || value == "0" {
                days[start.day, default: .init()].standingHours += 1
            } else if value.hasSuffix("Idle") || value == "1" {
                days[start.day, default: .init()].idleHours += 1
            }
        default:
            if let label = Self.eventNames[type] {
                days[start.day, default: .init()].events.append(HealthEvent(time: start, title: label))
            } else if let metric = HealthMetric(rawValue: type) {
                addMetric(metric, value: value, fields: fields, start: start)
            }
        }
    }

    private func addMetric(_ metric: HealthMetric, value: String, fields: [String: String], start: HealthTime) {
        let measurement: Double
        switch metric {
        case .mindfulness:
            guard let end = clock.time(fields["endDate"]), end.second >= start.second else { return }
            measurement = Double(end.second - start.second) / 60
        case .sexualActivity:
            measurement = 1
        default:
            guard let scalar = number(value) else { return }
            measurement = metric.normalized(scalar, unit: fields["unit"] ?? "")
        }
        guard measurement.isFinite, metric != .heartRate || measurement > 0 else { return }
        days[start.day, default: .init()].add(measurement, metric: metric, hour: start.hour)
    }

    private func addListening(from start: HealthTime, to end: HealthTime, decibels: Double, device: String) {
        var day = start.day
        var localStart = start.secondOfDay
        var remaining = end.second - start.second
        while remaining > 0 {
            let length = min(86_400 - localStart, remaining)
            audio[day, default: [:]][device, default: []].append(
                AudioSpan(lower: localStart, upper: localStart + length, decibels: decibels)
            )
            remaining -= length
            day = day.adding(1)
            localStart = 0
        }
    }

    private func addSleep(from start: HealthTime, to end: HealthTime, stage: SleepStage) {
        let timeline = SleepNight.timeline
        var day = start.secondOfDay < timeline.lowerBound ? start.day.adding(-1) : start.day
        var lower = start.localSecond - day.ordinal * 86_400
        var remaining = end.second - start.second
        while remaining > 0 {
            let length = min(timeline.upperBound - lower, remaining)
            sleep[day, default: []].append(SleepSpan(lower: lower, upper: lower + length, stage: stage))
            remaining -= length
            lower = timeline.lowerBound
            day = day.adding(1)
        }
    }

    private func startWorkout(_ fields: [String: String]) {
        guard let identifier = fields["workoutActivityType"], let start = clock.time(fields["startDate"]) else { return }
        let kind = identifier.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        let duration = number(fields["duration"]).map { HealthUnits.minutes($0, unit: fields["durationUnit"] ?? "") }
            ?? clock.time(fields["endDate"]).map { Double($0.second - start.second) / 60 }
            ?? 0
        let distance = number(fields["totalDistance"]).map { HealthUnits.kilometers($0, unit: fields["totalDistanceUnit"] ?? "km") }
        let energy = number(fields["totalEnergyBurned"]).map { HealthUnits.kilocalories($0, unit: fields["totalEnergyBurnedUnit"] ?? "kcal") }
        types["Workout:" + kind, default: 0] += 1
        recordCount += 1
        _ = countSource(fields)
        workout = WorkoutBuilder(workout: Workout(time: start, kind: kind, minutes: max(0, duration),
                                                  kilometers: distance, kilocalories: energy, averageHeartRate: nil))
    }

    private func addWorkoutStats(_ fields: [String: String]) {
        guard var current = workout, let type = fields["type"] else { return }
        let kind = Self.suffix(type)
        let unit = fields["unit"] ?? ""
        switch kind {
        case "HeartRate":
            current.workout.averageHeartRate = number(fields["average"])
        case "ActiveEnergyBurned":
            if let energy = number(fields["sum"]) {
                current.energy = (current.energy ?? 0) + HealthUnits.kilocalories(energy, unit: unit)
            }
        case "DistanceWalkingRunning", "DistanceCycling", "DistanceSwimming",
             "DistanceWheelchair", "DistanceDownhillSnowSports", "DistanceRowing", "DistanceSkatingSports":
            if let distance = number(fields["sum"]) {
                current.distance = (current.distance ?? 0) + HealthUnits.kilometers(distance, unit: unit)
            }
        default: break
        }
        workout = current
    }

    private func addRings(_ fields: [String: String]) {
        guard let key = fields["dateComponents"], let day = clock.day(key) else { return }
        let rings = ActivityRings(
            move: number(fields["activeEnergyBurned"]) ?? 0, moveGoal: number(fields["activeEnergyBurnedGoal"]) ?? 0,
            exercise: number(fields["appleExerciseTime"]) ?? 0, exerciseGoal: number(fields["appleExerciseTimeGoal"]) ?? 0,
            stand: number(fields["appleStandHours"]) ?? 0, standGoal: number(fields["appleStandHoursGoal"]) ?? 0
        )
        days[day, default: .init()].rings = rings
        types["ActivitySummary", default: 0] += 1
        recordCount += 1
    }

    private func addProfile(_ fields: [String: String]) {
        let labels = [
            ("DateOfBirth", "出生日期", ""), ("BiologicalSex", "生理性别", "HKBiologicalSex"),
            ("BloodType", "血型", "HKBloodType"), ("FitzpatrickSkinType", "皮肤类型", "HKFitzpatrickSkinType"),
            ("CardioFitnessMedicationsUse", "心肺适能用药标记", "HKCardioFitnessMedicationsUse")
        ]
        for (key, label, prefix) in labels {
            guard let value = fields["HKCharacteristicTypeIdentifier" + key], !value.isEmpty else { continue }
            let cleaned = prefix.isEmpty ? value : value.replacingOccurrences(of: prefix, with: "")
            if cleaned != "NotSet" { profile[label] = cleaned }
        }
    }

    private func countSource(_ fields: [String: String]) -> String {
        let source = fields["sourceName"] ?? ""
        if !source.isEmpty { sources[source, default: 0] += 1 }
        let raw = fields["device"] ?? ""
        if !raw.isEmpty {
            let device = deviceName(raw)
            if !device.isEmpty {
                devices[device, default: 0] += 1
                return device
            }
        }
        return source.isEmpty ? "未知耳机" : source
    }

    private func deviceName(_ raw: String) -> String {
        if let cached = deviceNames[raw] { return cached }
        let name: String
        if let start = raw.range(of: "name:")?.upperBound {
            name = raw[start...].prefix { $0 != "," && $0 != ">" }.trimmingCharacters(in: .whitespaces)
        } else {
            name = ""
        }
        if deviceNames.count < 512 { deviceNames[raw] = name }
        return name
    }

    private static func suffix(_ type: String) -> String {
        for prefix in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier", "HKDataType"] where type.hasPrefix(prefix) {
            return String(type.dropFirst(prefix.count))
        }
        return type
    }

    private func number(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    func report() throws -> HealthReport {
        for (day, names) in audio {
            try Task.checkCancellation()
            days[day, default: .init()].listening = finalizeListening(names)
        }
        audio.removeAll()
        for (day, segments) in sleep {
            try Task.checkCancellation()
            days[day, default: .init()].sleep = finalizeSleep(segments)
        }
        sleep.removeAll()
        guard !days.isEmpty else { throw HealthImportError.emptyExport }
        let rows = days.keys.sorted().map { HealthDayEntry(day: $0, data: days[$0]!) }
        return HealthReport(exported: exported, days: rows, sources: sources, devices: devices, types: types, profile: profile)
    }

    private func finalizeListening(_ devices: [String: [AudioSpan]]) -> ListeningDay {
        var result = ListeningDay()
        for (name, records) in devices {
            var usedUntil = 0
            var device = ListeningTotals()
            let ordered = records.sorted {
                if $0.lower != $1.lower { return $0.lower < $1.lower }
                if $0.upper != $1.upper { return $0.upper < $1.upper }
                return $0.decibels > $1.decibels
            }
            for record in ordered {
                var start = max(record.lower, usedUntil)
                guard record.upper > start else { continue }
                device.add(seconds: record.upper - start, decibels: record.decibels)
                while start < record.upper {
                    let hour = start / 3_600
                    let end = min(record.upper, (hour + 1) * 3_600)
                    result.byHour[hour, default: .init()].add(seconds: end - start, decibels: record.decibels)
                    result.deviceHours[name, default: [:]][hour, default: .init()].add(
                        seconds: end - start, decibels: record.decibels
                    )
                    start = end
                }
                usedUntil = record.upper
            }
            result.byDevice[name] = device
            result.total.merge(device)
        }
        return result
    }

    private func finalizeSleep(_ records: [SleepSpan]) -> SleepNight {
        let order: [SleepStage] = [.deep, .rem, .core, .awake, .unspecified, .inBed]
        let edges = records.flatMap {
            [SleepEdge(second: $0.lower, stage: $0.stage, change: 1), SleepEdge(second: $0.upper, stage: $0.stage, change: -1)]
        }.sorted { $0.second < $1.second }
        var counts: [SleepStage: Int] = [:]
        var stages: [SleepStage: Int] = [:]
        var intervals: [Range<Int>] = []
        var previous = edges.first?.second ?? 0
        for edge in edges {
            if edge.second > previous, let stage = order.first(where: { counts[$0, default: 0] > 0 }) {
                stages[stage, default: 0] += edge.second - previous
                if stage.asleep {
                    if let last = intervals.last, last.upperBound == previous {
                        intervals[intervals.count - 1] = last.lowerBound..<edge.second
                    } else {
                        intervals.append(previous..<edge.second)
                    }
                }
            }
            counts[edge.stage, default: 0] += edge.change
            previous = edge.second
        }
        return SleepNight(intervals: intervals, stages: stages)
    }
}
