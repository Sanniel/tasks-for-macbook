import SwiftUI
import TasksCore

// Views used by both the app and the widget.

/// The priority's mark: !!!, !!, !, nothing for Normal, ↓ for Low.
struct PriorityMark: View {
    let priority: Priority
    /// Point size of the exclamation marks; the Low arrow is drawn 3 pt smaller.
    var size: CGFloat = 14

    var body: some View {
        switch priority {
        case .normal:
            EmptyView()
        case .low:
            Image(systemName: "arrow.down")
                .font(.system(size: size - 3, weight: .heavy))
                .foregroundStyle(priority.color)
        default:
            Text(String(repeating: "!", count: priority.rawValue))
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(priority.color)
        }
    }
}

/// The area as a small colored label.
struct AreaPill: View {
    let area: Area

    var body: some View {
        Text(area.name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: area.colorHex), in: .rect(cornerRadius: 5))
    }
}
