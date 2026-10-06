import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                switch model.sidebarSelection ?? .all {
                case .all: TaskListView(areaID: nil)
                case .area(let id): TaskListView(areaID: id).id(id)
                case .done: DoneView()
                case .archive: ArchiveView()
                }
            }
            .onOpenURL { model.handle($0) }
            // Import confirmation lives on the split view, the error alert on its container,
            // so the two alerts never compete for the same view.
            .alert(
                "Import “\(model.pendingImport?.fileName ?? "")”?",
                isPresented: Binding(get: { model.pendingImport != nil }, set: { if !$0 { model.pendingImport = nil } }),
                presenting: model.pendingImport
            ) { pending in
                if pending.changes.isEmpty {
                    Button("OK") { model.pendingImport = nil }
                } else {
                    Button("Import") { model.confirmImport() }
                    Button("Cancel", role: .cancel) { model.pendingImport = nil }
                }
            } message: { pending in
                Text(pending.changes.isEmpty
                    ? "Everything in this backup is already in the app."
                    : pending.summary.description + " Nothing will be deleted.")
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
