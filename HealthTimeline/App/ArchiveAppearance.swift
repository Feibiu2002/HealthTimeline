import SwiftUI

enum ArchiveAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ArchiveStyle {
    static let background = adaptive(light: 0xEEF4F1, dark: 0x101819)
    static let wash = adaptive(light: 0xD7EBE4, dark: 0x173234)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1B282A)
    static let border = adaptive(light: 0xD8E5DF, dark: 0x304244)
    static let accent = adaptive(light: 0x0E685F, dark: 0x86DFCB)
    static let glassTint = adaptive(light: 0x95D3C0, dark: 0x2A7766).opacity(0.55)
    static let heart = adaptive(light: 0xB03957, dark: 0xF595AC)
    static let sleep = adaptive(light: 0x6353A6, dark: 0xC7B8F8)
    static let activity = adaptive(light: 0x2B63A1, dark: 0x9DCBF8)
    static let energy = adaptive(light: 0x9B511C, dark: 0xF4B478)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct ArchiveBackdrop: View {
    var body: some View {
        ArchiveStyle.background
            .overlay(alignment: .top) {
                LinearGradient(colors: [ArchiveStyle.wash, ArchiveStyle.wash.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 360)
            }
            .ignoresSafeArea()
    }
}

struct AppearanceMenu: View {
    @Binding var selection: ArchiveAppearance

    var body: some View {
        Menu {
            Picker("外观", selection: $selection) {
                ForEach(ArchiveAppearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.symbol)
                        .tag(appearance)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ArchiveActionIcon(symbol: selection.symbol)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("外观")
        .accessibilityValue(selection.title)
    }
}

struct ArchiveActionIcon: View {
    let symbol: String
    var highlighted = false

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(highlighted ? ArchiveStyle.accent : Color.primary)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .archiveGlass(in: Circle(), tint: highlighted ? ArchiveStyle.glassTint : nil)
    }
}

extension View {
    func archivePanel(cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return self
            .background(ArchiveStyle.card, in: shape)
            .overlay {
                shape.strokeBorder(ArchiveStyle.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func archiveGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self
                .background(tint ?? .clear, in: shape)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(ArchiveStyle.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}
