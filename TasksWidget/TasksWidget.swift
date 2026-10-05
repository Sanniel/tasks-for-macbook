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

/// Step-1 placeholder: shows the open task count read from the shared database.
/// Replaced by the real task list widget in step 4.
struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TasksWidget", provider: Provider()) { entry in
            VStack(alignment: .leading) {
                Text("Tasks").font(.headline)
                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks")
        .description("Your top tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let summary: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, summary: "3 open tasks")
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> Entry {
        do {
            let count = try SharedStore.openRepository().fetchTasks(TaskQuery(status: .open)).count
            return Entry(date: .now, summary: "\(count) open tasks")
        } catch {
            return Entry(date: .now, summary: "Database unavailable")
        }
    }
}
