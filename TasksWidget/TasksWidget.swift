import AppIntents
import SwiftUI
import TasksCore
import TasksStore
import WidgetKit

@main
struct TasksWidgetBundle: WidgetBundle {
    var body: some Widget {
        TasksWidget()
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TasksWidget", intent: TaskListConfigurationIntent.self, provider: Provider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Tasks")
        .description("Your top open tasks, in priority order.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

/// A task as the widget shows it, computed for the entry's date.
struct WidgetTask: Identifiable {
    let id: UUID
    let title: String
    let colorHex: String
    let priority: Priority  // effective
    let dueText: String?
    let isRed: Bool  // due today or overdue
}

struct TasksEntry: TimelineEntry {
    let date: Date
    let title: String
    let areaID: UUID?
    let tasks: [WidgetTask]
    /// Open, started tasks in the list, including ones that didn't fit.
    let totalCount: Int
    var message: String?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(
            date: .now, title: "Tasks", areaID: nil,
            tasks: [
                WidgetTask(id: UUID(), title: "Send monthly report", colorHex: "#F76B15", priority: .urgent, dueText: "Today", isRed: true),
                WidgetTask(id: UUID(), title: "Prepare workshop", colorHex: "#F76B15", priority: .high, dueText: "Friday", isRed: false),
                WidgetTask(id: UUID(), title: "Book dentist", colorHex: "#0090FF", priority: .raised, dueText: nil, isRed: false),
            ],
            totalCount: 3)
    }

    func snapshot(for configuration: TaskListConfigurationIntent, in context: Context) async -> TasksEntry {
        entry(at: .now, configuration: configuration, family: context.family)
    }

    /// One entry now and one at midnight (when effective priorities, overdue and
    /// not-started states change), then ask for a fresh timeline. Data changes
    /// trigger reloads from the app (WidgetCenter) and after the complete intent.
    func timeline(for configuration: TaskListConfigurationIntent, in context: Context) async -> Timeline<TasksEntry> {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return Timeline(
            entries: [
                entry(at: now, configuration: configuration, family: context.family),
                entry(at: midnight, configuration: configuration, family: context.family),
            ],
            policy: .atEnd)
    }

    static func rowLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemLarge, .systemExtraLarge: 10
        default: 4
        }
    }

    private func entry(at date: Date, configuration: TaskListConfigurationIntent, family: WidgetFamily) -> TasksEntry {
        let today = LocalDate(date)
        let areaID = configuration.area.flatMap { UUID(uuidString: $0.id) }
        do {
            let repo = try WidgetStore.repository.get()
            let areas = try repo.fetchAreas(includeArchived: true)
            let area = areaID.flatMap { id in areas.first { $0.id == id } }
            if areaID != nil, area == nil || area?.archivedAt != nil {
                return TasksEntry(
                    date: date, title: configuration.area?.name ?? "Tasks", areaID: nil, tasks: [], totalCount: 0,
                    message: "This area was archived. Edit the widget to pick another.")
            }
            let colors = Dictionary(areas.map { ($0.id, $0.colorHex) }, uniquingKeysWith: { a, _ in a })
            let open = TaskOrdering.openTasks(
                try repo.fetchTasks(TaskQuery(status: .open, areaID: areaID)), areas: areas, areaID: areaID, today: today)
                .filter { $0.isStarted(today: today) }
            let shown = open.prefix(Self.rowLimit(for: family)).map { task in
                WidgetTask(
                    id: task.id,
                    title: task.title,
                    colorHex: colors[task.areaID] ?? "#8D8D8D",
                    priority: EffectivePriority(task, today: today).value,
                    dueText: task.dueDate?.friendlyText(today: today),
                    isRed: task.isDueTodayOrOverdue(today: today))
            }
            return TasksEntry(
                date: date, title: area?.name ?? "Tasks", areaID: area?.id, tasks: shown, totalCount: open.count)
        } catch {
            return TasksEntry(
                date: date, title: "Tasks", areaID: nil, tasks: [], totalCount: 0,
                message: "Can't read tasks. Open the app once, then try again.")
        }
    }
}

// MARK: - Views

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TasksEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 5) {
            header
            if let message = entry.message {
                Spacer(minLength: 0)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                Label("No open tasks", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks) { task in
                    TaskLine(task: task, showArea: entry.areaID == nil, showDue: family != .systemSmall)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            if entry.totalCount > entry.tasks.count {
                Text("+\(entry.totalCount - entry.tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Link(destination: DeepLink.add(areaID: entry.areaID).url) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
            }
            .help("Add task")
        }
        .padding(.bottom, 4)
    }
}

private struct TaskLine: View {
    let task: WidgetTask
    let showArea: Bool
    let showDue: Bool

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(task.isRed ? Color.red : Color.clear)
                .frame(width: 2.5, height: 16)

            Button(intent: CompleteTaskIntent(taskID: task.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Link(destination: DeepLink.task(task.id).url) {
                HStack(spacing: 5) {
                    if showArea {
                        Circle().fill(Color(hex: task.colorHex)).frame(width: 7, height: 7)
                    }
                    Text(task.title)
                        .font(.system(size: 13, weight: task.isRed ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showDue, let due = task.dueText {
                        Text(due)
                            .font(.system(size: 12))
                            .foregroundStyle(task.isRed ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                    ZStack(alignment: .trailing) {
                        Color.clear
                        PriorityMark(priority: task.priority, size: 12)
                    }
                    .frame(width: 18, height: 14)
                }
            }
        }
    }
}
