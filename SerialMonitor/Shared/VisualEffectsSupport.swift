import SwiftUI

/// P2 中唯一允许使用 macOS 26 可用性判断的位置。
struct GlassContainerModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension View {
    func sessionGlass(cornerRadius: CGFloat = DesignTokens.containerCornerRadius) -> some View {
        modifier(GlassContainerModifier(cornerRadius: cornerRadius))
    }

    func sessionStateAnimation<V: Equatable>(_ value: V) -> some View {
        animation(.easeInOut(duration: 0.18), value: value)
    }
}
