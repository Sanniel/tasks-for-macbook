import SwiftUI
import TasksCore

@main
struct TasksApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        Window("Tasks", id: "main") {
            ContentView()
                .environment(model)
                // Room for sidebar + narrowed task list + inspector, so none gets clipped.
                .frame(minWidth: 980, minHeight: 500)
                #if DEBUG
                .onAppear { DebugSnapshot.scheduleIfRequested() }
                #endif
        }
        .defaultSize(width: 1180, height: 740)
        .commands { TaskCommands(model: model) }
    }
}

/// Menu bar commands. Priority shortcuts are the stored value: ⌘3 Urgent, ⌘2 High,
/// ⌘1 Raised, ⌘0 Normal, ⌘- Low.
struct TaskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { model.focusQuickAdd() }
                .keyboardShortcut("n")
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Backup…") { model.exportBackup() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Backup…") { model.chooseImportFile() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Task") {
            let selection = model.selectedTaskIDs
            // Actions read the selection when clicked; `selection` only drives enabled state.
            Button("Complete") { model.complete(model.selectedTaskIDs) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selection.isEmpty)
            Divider()
            ForEach(Priority.menuOrder, id: \.self) { priority in
                Button("Priority: \(priority.name)") { model.setPriority(priority, for: model.selectedTaskIDs) }
                    .keyboardShortcut(priority.shortcut, modifiers: .command)
                    .disabled(selection.isEmpty)
            }
            Divider()
            // Delete key in the list also archives (see TaskListView).
            Button("Archive") { model.archive(model.selectedTaskIDs) }
                .disabled(selection.isEmpty)
        }
    }
}
