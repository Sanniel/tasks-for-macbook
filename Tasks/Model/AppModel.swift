import AppKit
import Foundation
import Observation
import TasksCore
import TasksStore
import UniformTypeIdentifiers
import WidgetKit

enum SidebarItem: Hashable {
    case all
    case area(UUID)
    case done
    case archive
}

/// App state: an in-memory copy of all data, reloaded from the repository after
/// every write. All business rules come from TasksCore; this type only wires them
/// to the UI.
@MainActor @Observable
final class AppModel {
    private let repository: (any TaskRepository)?
    /// Running on throwaway sample data (`-demo`, Debug builds only).
    let isDemo: Bool

    private(set) var areas: [Area] = []  // including archived, by sortOrder
    private(set) var tasks: [TaskItem] = []  // every task, any status
    private(set) var subtasksByTask: [UUID: [Subtask]] = [:]
    /// Effective priority, overdue and not-started states depend on this; updated at midnight.
    private(set) var today = LocalDate.today()

    var sidebarSelection: SidebarItem? = .all {
        didSet { if sidebarSelection != oldValue { selectedTaskIDs = [] } }
    }
    var selectedTaskIDs: Set<UUID> = []
    /// Incremented to move keyboard focus to the quick-add field.
    private(set) var quickAddFocusRequest = 0
    var errorMessage: String?

    init(repository: (any TaskRepository)?, isDemo: Bool = false, startupError: String? = nil) {
        self.repository = repository
        self.isDemo = isDemo
        errorMessage = startupError
        guard repository != nil else { return }
        reload()
        seedFirstAreaIfNeeded()
        runPurge()
        observeDayAndActivation()
    }

    static func live() -> AppModel {
        do {
            #if DEBUG
            if CommandLine.arguments.contains("-demo") {
                let model = AppModel(repository: try DemoData.makeRepository(), isDemo: true)
                if CommandLine.arguments.contains("-selectFirst"), let first = model.openTasks(areaID: nil).first {
                    model.selectedTaskIDs = [first.id]
                }
                return model
            }
            #endif
            return AppModel(repository: try SharedStore.openRepository())
        } catch {
            return AppModel(repository: nil, startupError: "Could not open the database: \(error)")
        }
    }

    // MARK: Derived data

    var activeAreas: [Area] { areas.filter { $0.archivedAt == nil } }
    var archivedAreas: [Area] {
        areas.filter { $0.archivedAt != nil }.sorted { $0.archivedAt! > $1.archivedAt! }
    }

    func area(_ id: UUID) -> Area? { areas.first { $0.id == id } }
    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }
    func subtasks(of taskID: UUID) -> [Subtask] { subtasksByTask[taskID] ?? [] }

    /// Open tasks in active areas, in the shared sort order.
    func openTasks(areaID: UUID?) -> [TaskItem] {
        TaskOrdering.openTasks(tasks, areas: areas, areaID: areaID, today: today)
    }

    func openTaskCount(areaID: UUID?) -> Int {
        tasks.filter { $0.isOpen && (areaID == nil || $0.areaID == areaID) }.count
    }

    var doneTasks: [TaskItem] {
        TaskOrdering.sortedByCompletion(tasks.filter { $0.completedAt != nil && $0.archivedAt == nil })
    }

    /// Archived tasks shown individually. Tasks archived together with a still-archived
    /// area are listed under that area instead.
    var archivedTasks: [TaskItem] {
        tasks.filter { task in
            guard task.archivedAt != nil else { return false }
            return !(task.archivedWithArea && area(task.areaID)?.archivedAt != nil)
        }
        .sorted { $0.archivedAt! > $1.archivedAt! }
    }

    func tasksArchivedWith(areaID: UUID) -> Int {
        tasks.filter { $0.areaID == areaID && $0.archivedAt != nil && $0.archivedWithArea }.count
    }

    var selectedTask: TaskItem? {
        guard selectedTaskIDs.count == 1, let id = selectedTaskIDs.first else { return nil }
        return task(id)
    }

    // MARK: Tasks

    func addTask(title: String, areaID: UUID, priority: Priority, dueDate: LocalDate?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(title: trimmed, areaID: areaID, priority: priority, dueDate: dueDate)
        apply(ChangeSet(tasks: [task]))
    }

    /// Saves edits made in the detail view. Invalid tasks are not saved.
    func update(_ task: TaskItem) {
        guard task.validationErrors.isEmpty, let current = self.task(task.id), !current.hasSameContent(as: task) else { return }
        var t = task
        t.updatedAt = Date()
        apply(ChangeSet(tasks: [t]))
    }

    func setPriority(_ priority: Priority, for ids: Set<UUID>) {
        let now = Date()
        let changed = ids.compactMap(task).filter { $0.priority != priority }.map { task in
            var t = task
            t.priority = priority
            t.updatedAt = now
            return t
        }
        apply(ChangeSet(tasks: changed))
    }

    func complete(_ ids: Set<UUID>) {
        perform { repo in
            for id in ids { try repo.completeTask(id: id, now: Date()) }
        }
        selectedTaskIDs.subtract(ids)
    }

    func reopen(_ id: UUID) {
        perform { try $0.reopenTask(id: id, now: Date()) }
    }

    func archive(_ ids: Set<UUID>) {
        let now = Date()
        var changes = ChangeSet()
        for task in ids.compactMap(task) {
            changes.tasks += TaskActions.archive(task, now: now).tasks
        }
        apply(changes)
        selectedTaskIDs.subtract(ids)
    }

    func restoreTask(_ id: UUID) {
        perform { try $0.restoreTask(id: id, now: Date()) }
    }

    // MARK: Subtasks
    // Every subtask change also bumps the parent task's updatedAt, so "untouched"
    // (see TaskActions.reopen) means neither the task nor its checklist was edited.

    func addSubtask(to taskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let order = (subtasks(of: taskID).map(\.sortOrder).max() ?? -1) + 1
        applySubtaskChange(taskID: taskID, ChangeSet(subtasks: [Subtask(taskID: taskID, title: trimmed, sortOrder: order)]))
    }

    func updateSubtask(_ subtask: Subtask) {
        var s = subtask
        s.updatedAt = Date()
        applySubtaskChange(taskID: subtask.taskID, ChangeSet(subtasks: [s]))
    }

    func deleteSubtask(_ subtask: Subtask) {
        applySubtaskChange(taskID: subtask.taskID, ChangeSet(purgedSubtaskIDs: [subtask.id]))
    }

    private func applySubtaskChange(taskID: UUID, _ changes: ChangeSet) {
        var changes = changes
        if var parent = task(taskID) {
            parent.updatedAt = Date()
            changes.tasks.append(parent)
        }
        apply(changes)
    }

    // MARK: Areas

    func saveArea(id: UUID?, name: String, colorName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let id, var area = area(id) {
            area.name = trimmed
            area.colorName = colorName
            area.updatedAt = Date()
            apply(ChangeSet(areas: [area]))
        } else {
            let order = (areas.map(\.sortOrder).max() ?? -1) + 1
            let area = Area(name: trimmed, colorName: colorName, sortOrder: order)
            apply(ChangeSet(areas: [area]))
            sidebarSelection = .area(area.id)
        }
    }

    /// Default color for a new area: the next palette color no active area uses.
    var nextAreaColor: String {
        AreaColors.nextUnused(after: activeAreas.map(\.colorName))
    }

    /// Reorders active areas (sidebar drag and drop).
    func moveAreas(from source: IndexSet, to destination: Int) {
        var ordered = activeAreas
        ordered.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        let changed = ordered.enumerated().compactMap { index, area -> Area? in
            guard area.sortOrder != index else { return nil }
            var a = area
            a.sortOrder = index
            a.updatedAt = now
            return a
        }
        apply(ChangeSet(areas: changed))
    }

    func archiveArea(_ id: UUID) {
        if sidebarSelection == .area(id) { sidebarSelection = .all }
        perform { try $0.archiveArea(id: id, now: Date()) }
    }

    func restoreArea(_ id: UUID) {
        perform { try $0.restoreArea(id: id, now: Date()) }
    }

    // MARK: UI requests

    func focusQuickAdd() {
        if sidebarSelection == .done || sidebarSelection == .archive || sidebarSelection == nil {
            sidebarSelection = .all
        }
        quickAddFocusRequest += 1
    }

    // MARK: Plumbing

    private func apply(_ changes: ChangeSet) {
        guard !changes.isEmpty else { return }
        perform { try $0.apply(changes, at: Date()) }
    }

    private func perform(_ body: (any TaskRepository) throws -> Void) {
        guard let repository else { return }
        do {
            try body(repository)
        } catch {
            errorMessage = "\(error)"
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-reads everything. Data is small (one person's tasks), so this stays cheap.
    func reload() {
        guard let repository else { return }
        do {
            areas = try repository.fetchAreas(includeArchived: true)
            tasks = try repository.fetchTasks(TaskQuery(status: .all))
            subtasksByTask = Dictionary(grouping: try repository.fetchSubtasks(taskIDs: nil), by: \.taskID)
            if case .area(let id) = sidebarSelection, area(id)?.archivedAt != nil {
                sidebarSelection = .all
            }
            selectedTaskIDs = selectedTaskIDs.filter { task($0) != nil }
        } catch {
            errorMessage = "Could not load data: \(error)"
        }
    }

    /// A brand-new database gets one area so tasks can be added right away.
    private func seedFirstAreaIfNeeded() {
        guard areas.isEmpty, let repository, (try? repository.fetchTombstones().isEmpty) == true else { return }
        apply(ChangeSet(areas: [Area(name: "Private", colorName: AreaColors.names[0], sortOrder: 0)]))
    }

    private func runPurge() {
        perform { try Purge.run(on: $0, now: Date()) }
    }

    /// Called on midnight and when the app becomes active (picks up widget changes
    /// and a date change while the Mac slept).
    private func refresh() {
        let newToday = LocalDate.today()
        if newToday != today {
            today = newToday
            runPurge()
        } else {
            reload()
        }
    }

    private func observeDayAndActivation() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // The widget changed data (e.g. completed a task).
        ChangeNotifier.observe { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Backup (JSON export / merge import)

    struct PendingImport: Identifiable {
        let id = UUID()
        let fileName: String
        let changes: ChangeSet
        let summary: Backup.MergeSummary
    }

    /// A checked import waiting for the user's confirmation.
    var pendingImport: PendingImport?

    func exportBackup() {
        guard let repository else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Tasks Backup \(LocalDate.today().isoString).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Backup.encode(Backup.export(from: repository)).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error)"
        }
    }

    /// Reads and checks a backup, then asks for confirmation (see `confirmImport`).
    func chooseImportFile() {
        guard let repository else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try Backup.decode(Data(contentsOf: url))
            let plan = try Backup.mergePlan(document, into: repository)
            pendingImport = PendingImport(fileName: url.lastPathComponent, changes: plan.changes, summary: plan.summary)
        } catch {
            errorMessage = "\(error)"
        }
    }

    func confirmImport() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        apply(pending.changes)  // one transaction: all or nothing
    }

    // MARK: Deep links (from the widget)

    func handle(_ url: URL) {
        switch DeepLink(url: url) {
        case .add(let areaID):
            if let areaID, area(areaID)?.archivedAt == nil, area(areaID) != nil {
                sidebarSelection = .area(areaID)
            }
            focusQuickAdd()
        case .task(let id):
            reload()  // the widget may show something newer than our copy
            guard let task = task(id), task.isOpen else { return }
            if sidebarSelection != .area(task.areaID) { sidebarSelection = .all }
            selectedTaskIDs = [id]
        case nil:
            break
        }
    }
}
