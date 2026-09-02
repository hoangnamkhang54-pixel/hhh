import SwiftUI

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    var isSelected: Bool = false
}

class AppManagerViewModel: ObservableObject {
    @Published var installedApps: [AppItem] = []
    @Published var searchText: String = ""
    @Published var isDeleting: Bool = false
    @Published var statusMessage: String = ""

    func loadApps() {
        var apps: [AppItem] = []
        if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
            let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
            if let installedPlugins = workspace.perform(Selector(("allInstalledApplications"))).takeUnretainedValue() as? [AnyObject] {
                for app in installedPlugins {
                    if let bundleID = app.perform(Selector(("applicationIdentifier"))).takeUnretainedValue() as? String,
                       let localizedName = app.perform(Selector(("localizedName"))).takeUnretainedValue() as? String {
                        apps.append(AppItem(id: bundleID, name: localizedName))
                    }
                }
            }
        }
        DispatchQueue.main.async {
            self.installedApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func deleteSelectedApps() {
        let selected = installedApps.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        isDeleting = true
        statusMessage = "Đang xóa..."

        DispatchQueue.global(qos: .userInitiated).async {
            if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
                for app in selected {
                    _ = workspace.perform(Selector(("uninstallApplication:withOptions:")), with: app.id, with: nil)
                }
            }
            DispatchQueue.main.async {
                self.isDeleting = false
                self.loadApps()
            }
        }
    }

    func selectAll() {
        for i in 0..<installedApps.count {
            installedApps[i].isSelected = true
        }
    }

    func deselectAll() {
        for i in 0..<installedApps.count {
            installedApps[i].isSelected = false
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppManagerViewModel()

    var selectedCount: Int {
        viewModel.installedApps.filter { $0.isSelected }.count
    }

    var filteredApps: [AppItem] {
        if viewModel.searchText.isEmpty {
            return viewModel.installedApps
        } else {
            return viewModel.installedApps.filter {
                $0.name.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.id.localizedCaseInsensitiveContains(viewModel.searchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm kiếm ứng dụng...", text: $viewModel.searchText)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                HStack {
                    Button("Chọn tất cả") { viewModel.selectAll() }
                    Spacer()
                    Button("Bỏ chọn") { viewModel.deselectAll() }.foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.top, 5)

                List {
                    ForEach(filteredApps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.headline)
                                Text(app.id).font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(app.isSelected ? .blue : .gray)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let index = viewModel.installedApps.firstIndex(where: { $0.id == app.id }) {
                                viewModel.installedApps[index].isSelected.toggle()
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())

                if selectedCount > 0 {
                    Button(action: { viewModel.deleteSelectedApps() }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Xóa \(selectedCount) ứng dụng")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Batch Deleter")
            .onAppear { viewModel.loadApps() }
        }
    }
}

@main
struct AppBatchDeleterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
