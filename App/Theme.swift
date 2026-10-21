import SwiftUI
import UIKit

/// Dayline's paper-journal identity: warm paper background, ink text, one
/// rust accent. Dynamic colors keep dark mode honest - paper goes deep
/// brown-black, ink goes cream.
enum Theme {
    static let paper = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)
            : UIColor(red: 0.98, green: 0.965, blue: 0.937, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.12, blue: 0.10, alpha: 1)
            : UIColor(red: 1.0, green: 0.992, blue: 0.97, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.90, blue: 0.84, alpha: 1)
            : UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
    })
    static let accent = Color(red: 0.79, green: 0.44, blue: 0.29) // rust

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct JournalCardModifier: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ink.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func journalCard(padding: CGFloat = 14) -> some View {
        modifier(JournalCardModifier(padding: padding))
    }
}
