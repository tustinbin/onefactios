import SwiftUI

/// Shared readable-column + landscape tweaks so portrait stays phone-native
/// and landscape doesn’t leave a lonely left-aligned strip.
enum AppLayout {
    static let portraitContentWidth: CGFloat = 560
    static let landscapeContentWidth: CGFloat = 680

    static func contentMaxWidth(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        verticalSizeClass == .compact ? landscapeContentWidth : portraitContentWidth
    }

    static func horizontalPadding(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        verticalSizeClass == .compact ? 20 : 24
    }

    static func isLandscapePhone(verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .compact
    }
}

/// Centers a readable content column; widens slightly in landscape.
struct AppContentColumn: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var alignment: Alignment = .leading

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: AppLayout.contentMaxWidth(verticalSizeClass: verticalSizeClass),
                alignment: alignment
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    /// Constrain and center the main column (fixes landscape left-strip layout).
    func appContentColumn(alignment: Alignment = .leading) -> some View {
        modifier(AppContentColumn(alignment: alignment))
    }
}
