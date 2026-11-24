import SwiftUI
import UIKit

/// Dayline's design point of view: a **field journal, not a lifestyle
/// blog.** The previous pass had the right instinct (paper, ink, rust)
/// but the wrong execution — every surface used the same three moves
/// (16pt rounded card + soft shadow, rust for everything, blue/purple
/// pill tags), which is exactly the generic AI-app look. The rules that
/// keep this from sliding back:
///
/// 1. **One accent, used sparingly.** Rust is the mic (the one action),
///    the selected calendar day, and the favorite mark. Everything else
///    is ink on paper. If rust shows up in a third place, it is a bug.
/// 2. **Hairlines, not shadows.** Surfaces are separated by a 1px ink
///    hairline, never a drop shadow — except the mic, the one element
///    allowed to float.
/// 3. **Tags are words, not pills.** Tags and mood are set as plain
///    lowercase text, separated by middots, under a small-caps label.
///    No blue, no purple, no capsules anywhere in the app.
/// 4. **Serif has a job.** Serif is for dates and titles only. Body
///    text is the system font — readable, honest, not costume.
/// 5. **Photos are prints.** Media gets a thin frame and a plain-text
///    caption (time, video duration, Live), never a black pill badge.
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
    /// The one accent. See rule 1 above.
    static let accent = Color(red: 0.79, green: 0.44, blue: 0.29) // rust
    /// The only separator color in the app.
    static let hairline = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.16)
            : UIColor(white: 0.0, alpha: 0.10)
    })

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small-caps kicker label ("DAYLINE", "TAGS", "SCRAPBOOK").
    static func kicker(_ text: String) -> Text {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2)
    }

    /// A 1px rule. Use it to separate sections instead of a card.
    static func rule() -> some View {
        Rectangle().fill(hairline).frame(height: 1)
    }
}

/// The one card style in the app: paper surface, hairline edge, no
/// shadow. If a surface needs more emphasis than this, it needs a
/// different layout, not a heavier card.
struct JournalCardModifier: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func journalCard(padding: CGFloat = 14) -> some View {
        modifier(JournalCardModifier(padding: padding))
    }
}

/// Tags and mood as words under a small-caps label — never pills.
/// The mood, when present, is set in italic serif rust: it is the one
/// emotional word on the page, so it gets the one expressive treatment.
struct TagLine: View {
    var tags: [String]
    var mood: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Theme.kicker("Tags").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let mood, !mood.isEmpty {
                    Text(mood).font(Theme.display(13)).italic().foregroundStyle(Theme.accent)
                }
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// A 1px hairline divider.
struct Hairline: View {
    var body: some View { Theme.rule() }
}
