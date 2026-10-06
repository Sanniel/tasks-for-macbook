import SwiftUI
import TasksCore

/// "All tasks" (areaID nil) or one area's open tasks, in the shared sort order.
/// Not-started tasks are greyed out in their own section at the bottom.
struct TaskListView: View {
    @Environment(AppModel.self) private var model
    let areaID: UUID?

    var body: some View {
        @Bindable var model = model
        let tasks = model.openTasks(areaID: areaID)
        let started = tasks.filter { $0.isStarted(today: model.today) }
        let notStarted = tasks.filter { !$0.isStarted(today: model.today) }

        VStack(spacing: 0) {
            QuickAddBar(fixedAreaID: areaID)
            Divider()
            List(selection: $model.selectedTaskIDs) {
                ForEach(started) { task in
                    TaskRow(task: task, showArea: areaID == nil).tag(task.id)
                }
                if !notStarted.isEmpty {
                    Section("Not started yet") {
                        ForEach(notStarted) { task in
                            TaskRow(task: task, showArea: areaID == nil).tag(task.id)
                        }
                    }
                }
            }
            .onDeleteCommand { model.archive(model.selectedTaskIDs) }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("Complete") { model.complete(ids) }
                Menu("Priority") {
                    ForEach(Priority.menuOrder, id: \.self) { p in
                        Button(p.name) { model.setPriority(p, for: ids) }
                    }
                }
                Divider()
                Button("Archive") { model.archive(ids) }
            }
            .overlay {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No open tasks", systemImage: "checkmark.circle",
                        description: Text("Add one above, or press ⌘N."))
                }
            }
        }
        .navigationTitle(areaID.flatMap { model.area($0)?.name } ?? "All Tasks")
        .inspector(isPresented: Binding(
            get: { model.selectedTask?.isOpen == true },
            set: { if !$0 { model.selectedTaskIDs = [] } }
        )) {
            if let task = model.selectedTask {
                TaskDetailView(task: task)
                    .id(task.id)
                    .inspectorColumnWidth(min: 280, ideal: 300, max: 420)
            }
        }
    }
}

struct QuickAddBar: View {
    @Environment(AppModel.self) private var model
    /// When showing a single area, new tasks go there.
    let fixedAreaID: UUID?

    @State private var title = ""
    @State private var priority = Priority.normal
    @State private var dueDate: LocalDate?
    @AppStorage("quickAdd.lastAreaID") private var lastAreaID = ""
    @FocusState private var focused: Bool

    private var areaID: UUID? {
        if let fixedAreaID { return fixedAreaID }
        let active = model.activeAreas
        return active.first { $0.id.uuidString == lastAreaID }?.id ?? active.first?.id
    }

    var body: some View {
        // One row when there's room; controls wrap under the title when the
        // middle column is narrow (e.g. with the task inspector open).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                titleField.frame(minWidth: 160)
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                titleField
                HStack(spacing: 10) {
                    controls
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: model.quickAddFocusRequest) { focused = true }
        .onAppear { if model.quickAddFocusRequest > 0 { focused = true } }
    }

    private var titleField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint).font(.title3)
            TextField("New task", text: $title)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit(add)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if fixedAreaID == nil {
            Picker("Area", selection: Binding(
                get: { areaID },
                set: { lastAreaID = $0?.uuidString ?? "" }
            )) {
                ForEach(model.activeAreas) { area in
                    Text(area.name).tag(Optional(area.id))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        PriorityButtonGroup(priority: $priority)
        DueDateMenu(dueDate: $dueDate, today: model.today)
    }

    private func add() {
        guard let areaID, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.addTask(title: title, areaID: areaID, priority: priority, dueDate: dueDate)
        title = ""
        priority = .normal
        dueDate = nil
        focused = true
    }
}

/// One-click priority control: shows the priority, opens a menu to change it.
/// Normal priority shows nothing (a faint mark on hover, so it's still clickable).
struct PriorityMenu: View {
    let priority: Priority
    var effective: EffectivePriority? = nil
    let onChange: (Priority) -> Void
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(Priority.menuOrder, id: \.self) { p in
                Button {
                    onChange(p)
                } label: {
                    if p == priority { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        } label: {
            PriorityBadge(
                priority: effective?.value ?? priority,
                showsPlaceholder: hovering)
        }
        // .button + .plain draws the label as-is; .borderlessButton ignores custom fonts.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Priority: \((effective?.value ?? priority).name)")
    }
}

struct PriorityBadge: View {
    let priority: Priority
    var showsPlaceholder = false

    var body: some View {
        Group {
            if priority == .normal {
                Text("!").foregroundStyle(showsPlaceholder ? Color.secondary.opacity(0.35) : .clear)
                    .font(.system(size: 14, weight: .heavy))
            } else {
                PriorityMark(priority: priority)
            }
        }
        .frame(width: 26, alignment: .trailing)
    }
}

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

/// Joined row of buttons, Low → Urgent, each showing only its mark (Normal is empty).
/// Used when adding or editing a task.
struct PriorityButtonGroup: View {
    @Binding var priority: Priority

    private static let order: [Priority] = [.low, .normal, .raised, .high, .urgent]
    private let shape = RoundedRectangle(cornerRadius: 6)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.order.enumerated()), id: \.element) { index, p in
                if index > 0 {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1)
                }
                Button {
                    priority = p
                } label: {
                    // Color.clear keeps the empty Normal segment from collapsing.
                    ZStack { Color.clear; PriorityMark(priority: p, size: 12) }
                        .frame(width: 30, height: 22)
                        .background(p == priority ? Color.accentColor.opacity(0.2) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.name)
                .accessibilityLabel("Priority \(p.name)")
                .accessibilityAddTraits(p == priority ? .isSelected : [])
            }
        }
        .fixedSize()
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.secondary.opacity(0.35)))
    }
}

struct DueDateMenu: View {
    @Binding var dueDate: LocalDate?
    let today: LocalDate
    @State private var showingPicker = false

    var body: some View {
        Menu {
            Button("Today") { dueDate = today }
            Button("Tomorrow") { dueDate = today.adding(days: 1) }
            Button("In 3 Days") { dueDate = today.adding(days: 3) }
            Button("In a Week") { dueDate = today.adding(days: 7) }
            Button("Pick a Date…") { showingPicker = true }
            if dueDate != nil {
                Divider()
                Button("No Due Date") { dueDate = nil }
            }
        } label: {
            Label(dueDate?.friendlyText(today: today) ?? "Due", systemImage: "calendar")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showingPicker) {
            DatePicker(
                "Due date",
                selection: Binding(get: { (dueDate ?? today).date }, set: { dueDate = LocalDate($0) }),
                displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
        }
    }
}
