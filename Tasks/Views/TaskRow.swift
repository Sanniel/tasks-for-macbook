import SwiftUI
import TasksCore

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let showArea: Bool

    var body: some View {
        let today = model.today
        let red = task.isDueTodayOrOverdue(today: today)
        let started = task.isStarted(today: today)
        let subtasks = model.subtasks(of: task.id)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // Red marker for tasks due today or overdue.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(red ? Color.red : Color.clear)
                    .frame(width: 3)

                Button {
                    model.complete([task.id])
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Complete")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .fontWeight(red ? .medium : .regular)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if !started, let start = task.startDate {
                            Label("Starts \(start.friendlyText(today: today))", systemImage: "hourglass")
                        }
                        if let due = task.dueDate {
                            Label(due.friendlyText(today: today), systemImage: "calendar")
                                .foregroundStyle(red ? Color.red : Color.secondary)
                        }
                        if task.isRecurring {
                            Label(
                                task.isLastOccurrence ? "Last" : "Repeats",
                                systemImage: task.isLastOccurrence ? "repeat.1" : "repeat")
                                .help(task.isLastOccurrence ? "The series ends with this occurrence" : "Repeating task")
                        }
                        if !subtasks.isEmpty {
                            Label("\(subtasks.filter(\.isDone).count)/\(subtasks.count)", systemImage: "checklist")
                        }
                        if let notes = task.notes, !notes.isEmpty {
                            Image(systemName: "note.text").help(notes)
                        }
                    }
                    .labelStyle(CompactLabelStyle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                // Fixed-width columns so rows line up like a table.
                if showArea {
                    Group {
                        if let area = model.area(task.areaID) { AreaPill(area: area) }
                    }
                    .frame(width: TaskColumns.area, alignment: .leading)
                }
                PriorityMenu(priority: task.priority, effective: EffectivePriority(task, today: today)) {
                    model.setPriority($0, for: [task.id])
                }
                .frame(width: TaskColumns.priority, alignment: .trailing)
            }

            // Checklist items under the task, aligned with its title.
            ForEach(subtasks) { subtask in
                SubtaskLine(subtask: subtask)
            }
            .padding(.leading, TaskColumns.titleIndent)
        }
        .padding(.vertical, 3)
        .opacity(started ? 1 : 0.5)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
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

/// Widths of the right-hand columns in task rows.
enum TaskColumns {
    static let area: CGFloat = 110
    static let priority: CGFloat = 44
    /// Marker (3) + spacing (8) + checkbox (~16) + spacing (8): where the title starts.
    static let titleIndent: CGFloat = 35
}

/// A checklist item shown under its task in the list; can be ticked off directly.
struct SubtaskLine: View {
    @Environment(AppModel.self) private var model
    let subtask: Subtask

    var body: some View {
        HStack(spacing: 6) {
            Button {
                var s = subtask
                s.isDone.toggle()
                model.updateSubtask(s)
            } label: {
                Image(systemName: subtask.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(subtask.isDone ? "Mark not done" : "Mark done")
            Text(subtask.title)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? .secondary : .primary)
                .lineLimit(1)
        }
        .font(.callout)
    }
}
