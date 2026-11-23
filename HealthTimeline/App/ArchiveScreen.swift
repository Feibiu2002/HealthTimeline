import SwiftUI

enum ArchiveSection: String, CaseIterable, Identifiable {
    case overview = "概览", hearing = "耳朵", heart = "心脏", sleep = "睡眠"
    case activity = "活动", energy = "能量", mobility = "移动", devices = "设备"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "waveform.path"
        case .hearing: "headphones"
        case .heart: "heart"
        case .sleep: "moon.stars"
        case .activity: "figure.run"
        case .energy: "bolt"
        case .mobility: "figure.walk"
        case .devices: "applewatch"
        }
    }
}

struct ArchiveScreen: View {
    let report: HealthReport
    let importAnother: () -> Void

    @StateObject private var navigation: ArchiveNavigation

    private var section: ArchiveSection { navigation.section }
    private var dates: ClosedRange<HealthDay> { navigation.scope.dates }
    private var slice: HealthSlice { navigation.scope.slice }

    init(report: HealthReport, importAnother: @escaping () -> Void) {
        self.report = report
        self.importAnother = importAnother
        _navigation = StateObject(wrappedValue: ArchiveNavigation(report: report))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ArchiveSection.allCases) { item in
                        Button {
                            navigation.section = item
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .foregroundStyle(section == item ? .white : .primary)
                                .background(section == item ? ArchiveStyle.solidAccent : ArchiveStyle.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionReports(section: section, report: report, slice: slice, navigate: { navigation.section = $0 })
                }
                .frame(maxWidth: 800)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .id(section)
        }
        .sheet(isPresented: $navigation.customDates) {
            RangeSheet(available: report.dates ?? dates, current: dates) { chosen in
                select(chosen, title: "自定义")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("健康年表").font(.system(.largeTitle, design: .serif, weight: .semibold))
                Spacer()
                Button(action: importAnother) { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("导入另一份健康记录")
                    .buttonStyle(.bordered)
            }
            HStack {
                Text(datesCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 5)
                Menu {
                    Button("全部记录") { select(report.dates ?? dates, title: "全部") }
                    Button("最近 7 天") { recent(days: 7, title: "近 7 天") }
                    Button("最近 30 天") { recent(days: 30, title: "近 30 天") }
                    Button("最近一年") { recent(days: 365, title: "近一年") }
                    Button("自定义日期…") { navigation.customDates = true }
                } label: {
                    Label(navigation.scope.title, systemImage: "calendar").font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("报告日期，\(navigation.scope.title)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var datesCaption: String {
        let first = ArchiveFormat.date(dates.lowerBound)
        return dates.lowerBound == dates.upperBound ? first : "\(first) – \(ArchiveFormat.date(dates.upperBound))"
    }

    private func select(_ range: ClosedRange<HealthDay>, title: String) {
        navigation.scope = ArchiveNavigation.Scope(dates: range, slice: report.select(range), title: title)
    }

    private func recent(days count: Int, title: String) {
        guard let all = report.dates else { return }
        select(max(all.lowerBound, all.upperBound.adding(1 - count))...all.upperBound, title: title)
    }
}

@MainActor
private final class ArchiveNavigation: ObservableObject {
    struct Scope {
        let dates: ClosedRange<HealthDay>
        let slice: HealthSlice
        let title: String
    }

    @Published var section: ArchiveSection = .overview
    @Published var scope: Scope
    @Published var customDates = false

    init(report: HealthReport) {
        let today = HealthDay(date: .now)
        let dates = report.dates ?? today...today
        scope = Scope(dates: dates, slice: report.select(dates), title: "全部")
    }
}

private struct RangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let available: ClosedRange<HealthDay>
    let apply: (ClosedRange<HealthDay>) -> Void

    @StateObject private var fields: RangeFields

    init(available: ClosedRange<HealthDay>, current: ClosedRange<HealthDay>,
         apply: @escaping (ClosedRange<HealthDay>) -> Void) {
        self.available = available
        self.apply = apply
        _fields = StateObject(wrappedValue: RangeFields(dates: current))
    }

    var body: some View {
        NavigationStack {
            Form {
                let days = available.lowerBound.date...available.upperBound.date
                DatePicker("开始日期", selection: $fields.start, in: days, displayedComponents: .date)
                DatePicker("结束日期", selection: $fields.end, in: days, displayedComponents: .date)
            }
            .navigationTitle("报告日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        apply(fields.dates)
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
private final class RangeFields: ObservableObject {
    @Published var start: Date
    @Published var end: Date

    init(dates: ClosedRange<HealthDay>) {
        start = dates.lowerBound.date
        end = dates.upperBound.date
    }

    var dates: ClosedRange<HealthDay> {
        HealthDay(date: min(start, end))...HealthDay(date: max(start, end))
    }
}
