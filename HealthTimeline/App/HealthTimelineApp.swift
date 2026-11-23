import SwiftUI
import UniformTypeIdentifiers

@main
struct HealthTimelineApp: App {
    var body: some Scene {
        WindowGroup {
            HealthTimelineRoot()
                .environment(\.calendar, HealthDay.calendar)
                .environment(\.timeZone, HealthDay.calendar.timeZone)
                .tint(ArchiveStyle.accent)
        }
    }
}

@MainActor
private final class ReportImportModel: ObservableObject {
    @Published private(set) var report: HealthReport?
    @Published private(set) var reportID = UUID()
    @Published private(set) var progress: HealthImportProgress?
    @Published var message: String?
    @Published var selectFile = false

    private var task: Task<Void, Never>?
    private var request: UUID?

    func open(_ url: URL) {
        task?.cancel()
        let id = UUID()
        request = id
        message = nil
        progress = url.pathExtension.lowercased() == "zip" ? .expanding(0) : .reading(0)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let report = try HealthImport.read(url) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard self?.request == id else { return }
                        self?.progress = event
                    }
                }
                await self?.complete(id, report: report)
            } catch is CancellationError {
                await self?.complete(id)
            } catch {
                await self?.complete(id, error: error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        request = nil
        progress = nil
        task = nil
    }

    private func complete(_ id: UUID, report: HealthReport? = nil, error: String? = nil) {
        guard request == id else { return }
        if let report {
            self.report = report
            reportID = id
        }
        request = nil
        progress = nil
        task = nil
        message = error
    }
}

private struct HealthTimelineRoot: View {
    @AppStorage("archiveAppearance") private var appearance = ArchiveAppearance.system
    @StateObject private var importer = ReportImportModel()

    var body: some View {
        NavigationStack {
            Group {
                if let report = importer.report {
                    ArchiveScreen(report: report, appearance: $appearance) { importer.selectFile = true }
                        .id(importer.reportID)
                } else {
                    ImportLanding(appearance: $appearance) { importer.selectFile = true }
                }
            }
            .background { ArchiveBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(isPresented: $importer.selectFile, allowedContentTypes: [.zip, .xml]) { result in
            switch result {
            case .success(let url): importer.open(url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { importer.message = error.localizedDescription }
            }
        }
        .sheet(isPresented: Binding(get: { importer.progress != nil }, set: { _ in })) {
            if let progress = importer.progress {
                ImportProgressSheet(progress: progress, cancel: importer.cancel)
                    .presentationDetents([.height(290), .medium])
                    .interactiveDismissDisabled()
            }
        }
        .alert("无法导入", isPresented: Binding(get: { importer.message != nil }, set: { if !$0 { importer.message = nil } })) {
            Button("好") { importer.message = nil }
        } message: {
            Text(importer.message ?? "")
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}

private struct ImportLanding: View {
    @Binding var appearance: ArchiveAppearance
    let select: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("健康年表")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    AppearanceMenu(selection: $appearance)
                }
                importCard
                VStack(alignment: .leading, spacing: 12) {
                    Label("在 Apple「健康」的个人资料里选择「导出所有健康数据」，再把 ZIP 存到「文件」。",
                          systemImage: "square.and.arrow.up")
                    Label("健康数据在这台 iPhone 上处理", systemImage: "lock.shield")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ArchiveStyle.accent)
                .frame(width: 58, height: 58)
                .background(ArchiveStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("导入健康记录")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("查看心率、睡眠和活动随时间的变化。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: select) {
                Label("选择健康导出文件", systemImage: "folder")
                    .font(.headline)
                    .foregroundStyle(ArchiveStyle.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Capsule())
                    .archiveGlass(in: Capsule(), tint: ArchiveStyle.glassTint)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .archivePanel(cornerRadius: 30)
    }
}

private struct ImportProgressSheet: View {
    let progress: HealthImportProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("正在导入健康数据").font(.title2.bold())
            switch progress {
            case .expanding(let fraction):
                ProgressView(value: fraction) { Text("正在解压 ZIP") }
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .reading(let count):
                ProgressView()
                Text("正在读取健康记录 · \(count.formatted()) 条")
                    .foregroundStyle(.secondary)
            case .calculating:
                ProgressView()
                Text("正在按日期和设备汇总")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("取消导入", action: cancel).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .padding(.top, 12)
    }
}
