import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.14, green: 0.19, blue: 0.16)
    static let inkSoft = Color(red: 0.27, green: 0.33, blue: 0.30)
    static let muted = Color(red: 0.42, green: 0.48, blue: 0.44)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let surface = Color.white
    static let line = Color(red: 0.85, green: 0.87, blue: 0.85)
    static let accent = Color(red: 0.23, green: 0.37, blue: 0.30)
    static let accentSoft = Color(red: 0.91, green: 0.94, blue: 0.91)
    static let danger = Color(red: 0.54, green: 0.23, blue: 0.17)
    static let success = Color(red: 0.18, green: 0.42, blue: 0.28)
    static let successSoft = Color(red: 0.86, green: 0.93, blue: 0.88)

    static let paperGradient = LinearGradient(
        colors: [Color(red: 0.97, green: 0.98, blue: 0.97), paper],
        startPoint: .top,
        endPoint: .bottom
    )
}
