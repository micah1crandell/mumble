import SwiftUI

/// The visual grammar for Mumble's quiet, monochrome control surfaces.
enum AppStyle {
    enum Color {
        static let canvas = SwiftUI.Color.black.opacity(0.78)
        static let surface = SwiftUI.Color.white.opacity(0.08)
        static let surfaceMuted = SwiftUI.Color.white.opacity(0.055)
        static let ink = SwiftUI.Color.white.opacity(0.94)
        static let muted = SwiftUI.Color.white.opacity(0.56)
        static let line = SwiftUI.Color.white.opacity(0.15)
        static let teal = SwiftUI.Color.white.opacity(0.94)
        static let coral = SwiftUI.Color.white.opacity(0.94)
        static let gold = SwiftUI.Color.white.opacity(0.72)
        static let blue = SwiftUI.Color.white.opacity(0.8)
    }

    enum Font {
        static let display = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 14, weight: .regular, design: .rounded)
        static let bodyStrong = SwiftUI.Font.system(size: 14, weight: .semibold, design: .rounded)
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium, design: .rounded)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced).monospacedDigit()
    }

    enum Metric {
        static let small: CGFloat = 6
        static let standard: CGFloat = 12
        static let large: CGFloat = 20
        static let section: CGFloat = 28
        static let radius: CGFloat = 14
        static let smallRadius: CGFloat = 10
        static let border: CGFloat = 1
    }
}

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct AppSurface<Content: View>: View {
    var padding: CGFloat = AppStyle.Metric.large
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: AppStyle.Metric.radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.Metric.radius, style: .continuous)
                            .fill(AppStyle.Color.surface)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Metric.radius, style: .continuous)
                    .strokeBorder(AppStyle.Color.line, lineWidth: AppStyle.Metric.border)
            }
    }
}

struct AppWindowBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(AppStyle.Color.canvas)
    }
}

struct AppLabel: View {
    let text: String
    var color = AppStyle.Color.muted

    var body: some View {
        Text(text.uppercased())
            .font(AppStyle.Font.caption)
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

struct AppActionButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppStyle.Font.bodyStrong)
                .padding(.horizontal, AppStyle.Metric.standard)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? .black : AppStyle.Color.ink)
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius, style: .continuous)
                    .fill(.white)
            } else {
                RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius, style: .continuous)
                            .fill(AppStyle.Color.surfaceMuted)
                    }
                }
        }
        .overlay {
            if !prominent {
                RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius, style: .continuous)
                    .strokeBorder(AppStyle.Color.line, lineWidth: AppStyle.Metric.border)
            }
        }
    }
}