import SwiftUI
import TasksCore

/// Inspector for one task. Edits are saved as you make them (when valid).
struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var draft: TaskItem

    init(task: TaskItem) {
        self.task = task
        _draft = State(initialValue: task)
    }

    var body: some View {
        let today = model.today

        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.selectedTaskIDs = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Form {
                Section {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3)
                    Picker("Area", selection: $draft.areaID) {
                        ForEach(model.activeAreas) { area in
                            Text(area.name).tag(area.id)
                        }
                    }
                    LabeledContent("Priority") {
                        PriorityButtonGroup(priority: $draft.priority)
                    }
                }

                Section("Dates") {
                    OptionalDateRow(title: "Start", date: $draft.startDate, defaultDate: today)
                    OptionalDateRow(title: "Due", date: $draft.dueDate, defaultDate: today)
                    if let due = draft.dueDate, due <= today {
                        Label(due < today ? "Overdue" : "Due today", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.overdue)
                    }
                }

                Section("Repeat") {
                    RecurrenceEditor(rule: $draft.recurrence, dueDate: $draft.dueDate, today: today)
                }

                Section("Checklist") {
                    SubtaskEditor(taskID: task.id)
                }

                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 80)
                    .font(.body)
                }

                if !draft.validationErrors.isEmpty {
                    Section {
                        ForEach(draft.validationErrors, id: \.self) { error in
                            Label(error.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Palette.overdue)
                        }
                        Text("Changes are saved once this is fixed.").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Button("Complete", systemImage: "checkmark.circle") { model.complete([task.id]) }
                        Spacer()
                        Button("Archive", systemImage: "archivebox") { model.archive([task.id]) }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Palette.background)
        .onChange(of: draft) { model.update(draft) }
        .onChange(of: task) {
            // Pick up changes made elsewhere (e.g. priority from the list), without
            // clobbering the draft when only updatedAt moved.
            if !task.hasSameContent(as: draft) { draft = task }
        }
    }
}

extension TaskItem {
    /// Equal apart from `updatedAt`.
    func hasSameContent(as other: TaskItem) -> Bool {
        var a = self
        a.updatedAt = other.updatedAt
        return a == other
    }
}

extension TaskValidationError {
    var message: String {
        switch self {
        case .emptyTitle: "The title can't be empty."
        case .recurrenceWithoutDueDate: "A repeating task needs a due date."
        case .recurrenceWithoutDays: "Pick at least one day to repeat on."
        case .startDateAfterDueDate: "The start date is after the due date."
        }
    }
}

struct OptionalDateRow: View {
    let title: String
    @Binding var date: LocalDate?
    let defaultDate: LocalDate

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? defaultDate) : nil }
            ))
            Spacer()
            if date != nil {
                DatePicker(
                    title,
                    selection: Binding(get: { date ?? defaultDate }, set: { date = $0 }).asDate,
                    displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
        }
    }
}

struct RecurrenceEditor: View {
    @Binding var rule: RecurrenceRule?
    @Binding var dueDate: LocalDate?
    let today: LocalDate

    private enum Kind: Hashable { case weekly, monthly }

    var body: some View {
        Toggle("Repeat", isOn: Binding(get: { rule != nil }, set: setRepeats))
        if let current = rule {
            Picker("Every", selection: Binding(get: { kind(of: current) }, set: { setKind($0) })) {
                Text("Week").tag(Kind.weekly)
                Text("Month").tag(Kind.monthly)
            }
            .pickerStyle(.segmented)

            switch current.pattern {
            case .weekly(let weekdays):
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        DayToggle(label: day.shortName, isOn: weekdays.contains(day)) {
                            rule?.pattern = .weekly(weekdays: weekdays.symmetricDifference([day]))
                        }
                    }
                }
            case .monthly(let days):
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(DayToggle.size), spacing: 3), count: 7), spacing: 3) {
                    ForEach(1...31, id: \.self) { day in
                        DayToggle(label: "\(day)", isOn: days.contains(day)) {
                            rule?.pattern = .monthly(days: days.symmetricDifference([day]))
                        }
                    }
                }
                if days.contains(where: { $0 >= 29 }) {
                    Text("In shorter months, days that don't exist fall on the last day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            DatePicker(
                "Ends",
                selection: Binding(get: { current.endDate }, set: { rule?.endDate = $0 }).asDate,
                displayedComponents: .date)
                .datePickerStyle(.field)

            if let due = dueDate, current.nextOccurrence(after: due) == nil {
                Label("The series ends with this occurrence.", systemImage: "repeat.1")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func kind(of rule: RecurrenceRule) -> Kind {
        if case .weekly = rule.pattern { return .weekly }
        return .monthly
    }

    private func setRepeats(_ on: Bool) {
        guard on else {
            rule = nil
            return
        }
        // A repeating task needs a due date; default to today.
        let due = dueDate ?? today
        dueDate = due
        let threeMonths = Calendar.current.date(byAdding: .month, value: 3, to: due.date)!
        rule = RecurrenceRule(pattern: .weekly(weekdays: [due.weekday]), endDate: LocalDate(threeMonths))
    }

    private func setKind(_ kind: Kind) {
        let due = dueDate ?? today
        switch kind {
        case .weekly: rule?.pattern = .weekly(weekdays: [due.weekday])
        case .monthly: rule?.pattern = .monthly(days: [due.day])
        }
    }
}

private struct DayToggle: View {
    static let size: CGFloat = 26

    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .frame(width: Self.size, height: 22)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 5))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

extension Weekday {
    var shortName: String {
        switch self {
        case .monday: "Mo"
        case .tuesday: "Tu"
        case .wednesday: "We"
        case .thursday: "Th"
        case .friday: "Fr"
        case .saturday: "Sa"
        case .sunday: "Su"
        }
    }
}

struct SubtaskEditor: View {
    @Environment(AppModel.self) private var model
    let taskID: UUID
    @State private var newTitle = ""

    var body: some View {
        ForEach(model.subtasks(of: taskID)) { subtask in
            SubtaskRow(subtask: subtask)
        }
        TextField("Add item", text: $newTitle, prompt: Text("Add item"))
            .labelsHidden()
            .onSubmit {
                model.addSubtask(to: taskID, title: newTitle)
                newTitle = ""
            }
    }
}

private struct SubtaskRow: View {
    @Environment(AppModel.self) private var model
    let subtask: Subtask
    @State private var title: String
    @FocusState private var editing: Bool

    init(subtask: Subtask) {
        self.subtask = subtask
        _title = State(initialValue: subtask.title)
    }

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { subtask.isDone },
                set: { done in
                    var s = subtask
                    s.isDone = done
                    model.updateSubtask(s)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            TextField("Item", text: $title, prompt: Text("Item"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? .secondary : .primary)
                .focused($editing)
                .onSubmit(saveTitle)
                .onChange(of: editing) { if !editing { saveTitle() } }
            Button {
                model.deleteSubtask(subtask)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove item")
        }
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        var s = subtask
        s.title = trimmed
        model.updateSubtask(s)
    }
}
