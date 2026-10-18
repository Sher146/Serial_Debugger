import SwiftUI

/// Semantic text roles. Sizes follow Apple HIG "macOS built-in text styles";
/// the actual rendered size is `baseSize × AppFontScale.multiplier`.
enum AppFontRole {
    case title
    case title3
    case headline
    case body
    case callout
    case subheadline
    case caption
    case mono
    case control

    var baseSize: CGFloat {
        switch self {
        case .title: 17      // HIG Title 2
        case .title3: 15     // HIG Title 3
        case .headline: 13   // HIG Headline
        case .body: 13       // HIG Body (macOS default)
        case .callout: 12    // HIG Callout
        case .subheadline: 11 // HIG Subheadline
        case .caption: 10    // HIG Caption (macOS minimum)
        case .mono: 12
        case .control: 13    // macOS control content font
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .title, .title3, .headline, .subheadline: .semibold
        case .body, .callout, .caption, .mono, .control: .regular
        }
    }

    var design: Font.Design {
        self == .mono ? .monospaced : .default
    }
}

private struct AppFontScaleKey: EnvironmentKey {
    static let defaultValue: AppFontScale = .standard
}

extension EnvironmentValues {
    var appFontScale: AppFontScale {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    let role: AppFontRole
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(.system(size: role.baseSize * scale.multiplier, weight: weight ?? role.defaultWeight, design: role.design))
    }
}

extension View {
    func appFont(_ role: AppFontRole, weight: Font.Weight? = nil) -> some View {
        modifier(AppFontModifier(role: role, weight: weight))
    }

    /// Rounded opaque surface used for panels and text boxes so every container
    /// shares the same corner radius and style.
    func containerSurface(cornerRadius: CGFloat = DesignTokens.containerCornerRadius) -> some View {
        background(Color.consoleSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor))
            }
    }
}

enum DesignTokens {
    /// 8 pt grid: related controls 8, groups 16, sections/window content margin 20.
    static let compactSpacing: CGFloat = 8
    /// Shared vertical inset between console/send controls and their surfaces.
    static let panelVerticalSpacing: CGFloat = 2
    static let standardSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    /// Single horizontal inset shared by every toolbar/panel/row so left edges align.
    static let contentInset: CGFloat = 20
    /// Shared height for the top bars (console + preset) so their edges align.
    static let barHeight: CGFloat = 44
    static let controlCornerRadius: CGFloat = 6
    static let containerCornerRadius: CGFloat = 10
    static let toolbarPortPickerWidth: CGFloat = 360
    static let toolbarIconTargetSize: CGFloat = 32

    /// Resolved monospaced point size for the console/editors given the global scale.
    static func monoFontSize(scale: AppFontScale) -> CGFloat {
        AppFontRole.mono.baseSize * scale.multiplier
    }
}

extension Color {
    static let sessionConnected = Color(red: 0.09, green: 0.50, blue: 0.24)
    static let sessionAttention = Color(red: 0.71, green: 0.28, blue: 0.03)
    static let sessionError = Color(red: 0.85, green: 0.18, blue: 0.13)
    static let consoleSurface = Color(nsColor: .textBackgroundColor)
}
