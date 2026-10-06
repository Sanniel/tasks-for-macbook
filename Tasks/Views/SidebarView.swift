import SwiftUI
import TasksCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var editingArea: AreaDraft?
    @State private var archivingArea: Area?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Label("All Tasks", systemImage: "tray.full")
                .badge(model.openTaskCount(areaID: nil))
                .tag(SidebarItem.all)

            Section("Areas") {
                ForEach(model.activeAreas) { area in
                    Label {
                        Text(area.name)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(Palette.area(area.colorName))
                    }
                    .badge(model.openTaskCount(areaID: area.id))
                    .tag(SidebarItem.area(area.id))
                    .contextMenu {
                        Button("Edit…") { editingArea = AreaDraft(area) }
                        Button("Archive…") { archivingArea = area }
                    }
                }
                .onMove { model.moveAreas(from: $0, to: $1) }
            }

            Section {
                Label("Done", systemImage: "checkmark.circle").tag(SidebarItem.done)
                Label("Archive", systemImage: "archivebox").tag(SidebarItem.archive)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if model.isDemo {
                    Label("Demo data – not saved", systemImage: "theatermasks")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Button {
                    editingArea = AreaDraft(colorName: model.nextAreaColor)
                } label: {
                    Label("New Area", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .sheet(item: $editingArea) { draft in
            AreaEditor(draft: draft)
        }
        .confirmationDialog(
            "Archive “\(archivingArea?.name ?? "")”?",
            isPresented: Binding(get: { archivingArea != nil }, set: { if !$0 { archivingArea = nil } }),
            presenting: archivingArea
        ) { area in
            Button("Archive Area") { model.archiveArea(area.id) }
            Button("Cancel", role: .cancel) {}
        } message: { area in
            Text(archiveMessage(for: area))
        }
    }

    private func archiveMessage(for area: Area) -> String {
        let count = model.openTaskCount(areaID: area.id)
        let tasks = count == 0
            ? "It has no open tasks."
            : "Its \(count) open task\(count == 1 ? "" : "s") will be archived with it."
        return "\(tasks) Completed tasks stay in Done. You can restore it from the Archive "
            + "for \(Retention.purgeAfterDays) days; after that it is permanently deleted."
    }
}

struct AreaDraft: Identifiable {
    let id = UUID()
    var areaID: UUID?
    var name = ""
    var colorName: String

    init(colorName: String) {
        self.colorName = colorName
    }

    init(_ area: Area) {
        areaID = area.id
        name = area.name
        colorName = area.colorName
    }
}

struct AreaEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: AreaDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.areaID == nil ? "New Area" : "Edit Area").font(.headline)
            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack(spacing: 8) {
                ForEach(AreaColors.names, id: \.self) { name in
                    Button {
                        draft.colorName = name
                    } label: {
                        Circle()
                            .fill(Palette.area(name))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if draft.colorName == name {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.saveArea(id: draft.areaID, name: draft.name, colorName: draft.colorName)
        dismiss()
    }
}
