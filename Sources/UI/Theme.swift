import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.020, blue: 0.078)
    static let surface = Color(red: 0.086, green: 0.039, blue: 0.149)
    static let elevated = Color(red: 0.145, green: 0.075, blue: 0.21)
    static let accent = Color(red: 1, green: 0.165, blue: 0.522)
    static let cyan = Color(red: 0, green: 0.949, blue: 0.996)
    static let orange = accent
    static let secondary = Color(red: 0.60, green: 0.60, blue: 0.68)
}

extension View {
    func premiumBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .tint(Theme.orange)
    }
}
