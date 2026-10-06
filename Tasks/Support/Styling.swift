import SwiftUI
import TasksCore

enum AreaPalette {
    static let colors = [
        "#E5484D", "#F76B15", "#E2A336", "#46A758", "#12A594",
        "#0090FF", "#3E63DD", "#8E4EC6", "#D6409F", "#8D8D8D",
    ]
}

extension Color {
    /// `#RRGGBB`; grey if malformed.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension Priority {
    /// Ordered for menus: most important first.
    static let menuOrder: [Priority] = [.urgent, .high, .raised, .normal, .low]

    var color: Color {
        switch self {
        case .urgent: .red
        case .high: .orange
        case .raised: .yellow
        case .normal: .secondary
        case .low: .blue
        }
    }

    /// Menu shortcut: the stored value itself (⌘3 … ⌘0), and ⌘- for Low (-1).
    var shortcut: KeyEquivalent {
        switch self {
        case .low: "-"
        default: KeyEquivalent(Character(String(rawValue)))
        }
    }
}

extension LocalDate {
    var date: Date { startOfDay() }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the next week, else "Oct 12"
    /// (with the year when it isn't this year).
    func friendlyText(today: LocalDate) -> String {
        switch today.days(until: self) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return date.formatted(.dateTime.weekday(.wide))
        default:
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return year == today.year ? date.formatted(style) : date.formatted(style.year())
        }
    }
}

extension Binding where Value == LocalDate {
    /// Bridges a date-only value to DatePicker's `Date`.
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date }, set: { wrappedValue = LocalDate($0) })
    }
}
