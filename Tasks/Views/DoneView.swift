import SwiftUI
import TasksCore

/// Completed tasks, newest completion first. Each can be reopened.
struct DoneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tasks = model.doneTasks
        List {
            Section {
                ForEach(tasks) { task in
                    HStack(spacing: 10) {
                        Button {
                            model.reopen(task.id)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Reopen")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).strikethrough().foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                AreaTag(areaID: task.areaID)
                                if let completed = task.completedAt {
                                    Text("Completed \(LocalDate(completed).friendlyText(today: model.today).lowercasedIfRelative)")
                                    Text(PurgeCountdown.text(since: completed))
                                }
                                if task.isRecurring { Image(systemName: "repeat") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reopen") { model.reopen(task.id) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                if !tasks.isEmpty {
                    Text("Completed tasks are permanently removed \(Retention.purgeAfterDays) days after completion.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("Nothing completed yet", systemImage: "checkmark.circle")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle("Done")
    }
}

/// Archived areas and tasks, with restore and days left before permanent removal.
struct ArchiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let areas = model.archivedAreas
        let tasks = model.archivedTasks
        List {
            if !areas.isEmpty {
                Section("Areas") {
                    ForEach(areas) { area in
                        HStack(spacing: 10) {
                            Circle().fill(Palette.area(area.colorName)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(area.name)
                                HStack(spacing: 10) {
                                    let count = model.tasksArchivedWith(areaID: area.id)
                                    Text("\(count) task\(count == 1 ? "" : "s")")
                                    if let archived = area.archivedAt { Text(PurgeCountdown.text(since: archived)) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { model.restoreArea(area.id) }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if !tasks.isEmpty {
                Section("Tasks") {
                    ForEach(tasks) { task in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                HStack(spacing: 10) {
                                    AreaTag(areaID: task.areaID)
                                    if task.completedAt != nil { Text("Completed") }
                                    if let archived = task.archivedAt {
                                        Text(PurgeCountdown.text(since: Retention.retentionStart(of: task) ?? archived))
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { model.restoreTask(task.id) }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .overlay {
            if areas.isEmpty && tasks.isEmpty {
                ContentUnavailableView(
                    "Archive is empty", systemImage: "archivebox",
                    description: Text("Archived items are kept here for \(Retention.purgeAfterDays) days."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle("Archive")
    }
}

struct AreaTag: View {
    @Environment(AppModel.self) private var model
    let areaID: UUID

    var body: some View {
        if let area = model.area(areaID) {
            HStack(spacing: 4) {
                Circle().fill(Palette.area(area.colorName)).frame(width: 7, height: 7)
                Text(area.name)
            }
        }
    }
}

enum PurgeCountdown {
    static func text(since date: Date) -> String {
        switch Retention.daysUntilPurge(after: date, now: Date()) {
        case 0: "Removed today"
        case 1: "1 day left"
        case let n: "\(n) days left"
        }
    }
}

private extension String {
    /// "Completed today" rather than "Completed Today"; dates are left alone.
    var lowercasedIfRelative: String {
        ["Today", "Yesterday", "Tomorrow"].contains(self) ? lowercased() : "on \(self)"
    }
}
