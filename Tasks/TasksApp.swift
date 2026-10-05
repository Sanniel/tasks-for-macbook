import SwiftUI
import TasksCore
import TasksStore

@main
struct TasksApp: App {
    var body: some Scene {
        WindowGroup {
            SetupStatusView()
        }
    }
}

/// Step-1 placeholder: confirms the shared database opens from the App Group.
/// Replaced by the real task lists in step 3.
struct SetupStatusView: View {
    @State private var status = "Opening database…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks").font(.largeTitle.bold())
            Text(status).textSelection(.enabled)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 200, alignment: .topLeading)
        .task { load() }
    }

    private func load() {
        do {
            let repository = try SharedStore.openRepository()
            let areas = try repository.fetchAreas(includeArchived: false)
            let tasks = try repository.fetchTasks(TaskQuery(status: .open))
            status = """
                Database: \(try SharedStore.databaseURL().path)
                \(areas.count) areas, \(tasks.count) open tasks
                """
        } catch {
            status = "Could not open database: \(error)"
        }
    }
}
