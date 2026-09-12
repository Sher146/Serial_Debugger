import SwiftUI

enum DesignTokens {
    static let compactSpacing: CGFloat = 8
    static let standardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let controlCornerRadius: CGFloat = 8
    static let containerCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 16
    static let toolbarPortPickerWidth: CGFloat = 360
    static let toolbarIconTargetSize: CGFloat = 32
    static let consoleFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let statusFont = Font.system(size: 12, weight: .medium)
}

extension Color {
    static let sessionConnected = Color(red: 0.09, green: 0.50, blue: 0.24)
    static let sessionAttention = Color(red: 0.71, green: 0.28, blue: 0.03)
    static let sessionError = Color(red: 0.85, green: 0.18, blue: 0.13)
    static let consoleSurface = Color(nsColor: .textBackgroundColor)
}
