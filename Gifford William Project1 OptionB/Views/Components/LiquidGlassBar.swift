import SwiftUI

/// Sticky bottom chrome with a liquid-glass look. Content scrolls underneath.
struct LiquidGlassBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background { barBackground }
    }

    @ViewBuilder
    private var barBackground: some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.line.opacity(0.55))
                        .frame(height: 0.5)
                }
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.line.opacity(0.7))
                        .frame(height: 0.5)
                }
        }
    }
}

struct LiquidIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .modifier(LiquidControlChrome(isActive: isActive))
    }
}

private struct LiquidControlChrome: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content
                .glassEffect(
                    isActive ? .regular.tint(AppTheme.accentSoft) : .regular.interactive(),
                    in: .circle
                )
        } else {
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().stroke(AppTheme.line.opacity(0.8), lineWidth: 0.5)
                        }
                )
        }
    }
}
