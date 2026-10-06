import SwiftUI
import TasksCore

/// The app's muted, earthy palette (see design/palette-preview.html). Named colors with light
/// and dark variants live in Shared/Palette.xcassets, compiled into the app and widget.
enum Palette {
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let text = Color("TextPrimary")
    static let secondaryText = Color("TextSecondary")
    static let tertiaryText = Color("TextTertiary")
    static let separator = Color("Separator")
    /// Overdue and due-today text and row marker.
    static let overdue = Color("Overdue")
    /// Urgent priority marks.
    static let urgent = Color("Urgent")
    /// Greyed-out text of tasks that haven't started yet.
    static let notStarted = Color("NotStarted")

    /// An area color by name (`AreaColors.names`); unknown names use the fallback.
    static func area(_ name: String) -> Color {
        Color("Area/" + (AreaColors.names.contains(name) ? name : AreaColors.fallback))
    }
}

extension Priority {
    /// Ordered for menus: most important first.
    static let menuOrder: [Priority] = [.urgent, .high, .raised, .normal, .low]

    /// Urgent uses the overdue red, High the urgent ochre; lower levels are quiet.
    var color: Color {
        switch self {
        case .urgent: Palette.overdue
        case .high: Palette.urgent
        case .raised, .normal: Palette.secondaryText
        case .low: Palette.tertiaryText
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

    /// Like `friendlyText`, but an overdue date reads "Overdue · 2 days", so overdue
    /// doesn't rely on color alone.
    func dueText(today: LocalDate) -> String {
        let late = days(until: today)
        guard late > 0 else { return friendlyText(today: today) }
        return "Overdue · \(late) day\(late == 1 ? "" : "s")"
    }
}

extension Binding where Value == LocalDate {
    /// Bridges a date-only value to DatePicker's `Date`.
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date }, set: { wrappedValue = LocalDate($0) })
    }
}
