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

    @Binding var appearance: ArchiveAppearance
    @StateObject private var navigation: ArchiveNavigation

    private var section: ArchiveSection { navigation.section }
    private var dates: ClosedRange<HealthDay> { navigation.scope.dates }
    private var slice: HealthSlice { navigation.scope.slice }
    private let contentWidth: CGFloat = 680

    init(report: HealthReport, appearance: Binding<ArchiveAppearance>, importAnother: @escaping () -> Void) {
        self.report = report
        self.importAnother = importAnother
        _appearance = appearance
        _navigation = StateObject(wrappedValue: ArchiveNavigation(report: report))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionReports(section: section, report: report, slice: slice)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity)
        }
        .id(section)
        .safeAreaInset(edge: .top, spacing: 0) {
            glassHeader
                .background {
                    LinearGradient(stops: [
                        .init(color: ArchiveStyle.wash, location: 0),
                        .init(color: ArchiveStyle.wash, location: 0.60),
                        .init(color: ArchiveStyle.wash.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                }
        }
        .sheet(isPresented: $navigation.customDates) {
            RangeSheet(available: report.dates ?? dates, current: dates) { chosen in
                select(chosen, title: "自定义")
            }
        }
    }

    @ViewBuilder
    private var glassHeader: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { header }
        } else {
            header
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("健康年表")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    AppearanceMenu(selection: $appearance)
                    Button(action: importAnother) {
                        ArchiveActionIcon(symbol: "square.and.arrow.down", highlighted: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("导入另一份健康记录")
                }
                HStack(spacing: 10) {
                    Text(datesCaption)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    dateFilter
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 20)
            sectionPicker
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
    }

    private var dateFilter: some View {
        Menu {
            Button("全部记录") { select(report.dates ?? dates, title: "全部") }
            Button("最近 7 天") { recent(days: 7, title: "近 7 天") }
            Button("最近 30 天") { recent(days: 30, title: "近 30 天") }
            Button("最近一年") { recent(days: 365, title: "近一年") }
            Button("自定义日期…") { navigation.customDates = true }
        } label: {
            HStack(spacing: 6) {
                Label(navigation.scope.title, systemImage: "calendar")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .archiveGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("报告日期")
        .accessibilityValue(navigation.scope.title)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ArchiveSection.allCases) { item in
                    let selected = section == item
                    Button {
                        navigation.section = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? ArchiveStyle.accent : Color.primary)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                            .archiveGlass(in: Capsule(), tint: selected ? ArchiveStyle.glassTint : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never, axes: .horizontal)
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
