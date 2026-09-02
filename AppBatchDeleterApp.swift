import SwiftUI

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    var isSelected: Bool = false
}

class AppManagerViewModel: ObservableObject {
    @Published var installedApps: [AppItem] = []
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
                        if !bundleID.hasPrefix("com.apple.") {
                            apps.append(AppItem(id: bundleID, name: localizedName))
                        }
                    }
                }
            }
        }
        self.installedApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppManagerViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach($viewModel.installedApps) { $app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Text(app.id).foregroundColor(.gray).font(.caption)
                        }
                    }
                }
                .onAppear { viewModel.loadApps() }
                .navigationTitle("App Batch Deleter")
            }
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
