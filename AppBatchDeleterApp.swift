import SwiftUI
import Foundation

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let bundleURL: URL?
    var isSelected: Bool = false
}

// Execution Helper chay lenh Root bang posix_spawn
func runRootCommand(_ command: String) -> Int32 {
    let possibleShells = [
        "/var/jb/bin/sh",
        "/var/jb/usr/bin/sh",
        "/bin/sh",
        "/usr/bin/sh"
    ]
    
    var shellPath = "/bin/sh"
    for path in possibleShells {
        if FileManager.default.fileExists(atPath: path) {
            shellPath = path
            break
        }
    }

    var pid: pid_t = 0
    var args: [UnsafeMutablePointer<CChar>?] = [
        strdup(shellPath),
        strdup("-c"),
        strdup(command),
        nil
    ]
    defer {
        for arg in args where arg != nil {
            free(arg)
        }
    }

    let status = posix_spawn(&pid, shellPath, nil, nil, &args, nil)
    if status == 0 {
        var exitStatus: Int32 = 0
        waitpid(pid, &exitStatus, 0)
        return exitStatus
    }
    return status
}

class AppManagerViewModel: ObservableObject {
    @Published var installedApps: [AppItem] = []
    @Published var searchText: String = ""
    @Published var isDeleting: Bool = false
    @Published var isLoading: Bool = true
    @Published var statusMessage: String = ""

    func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            var appsDict: [String: AppItem] = [:]
            
            if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
                
                var rawApps: [AnyObject] = []
                let allAppsSel = Selector(("allApplications"))
                if workspace.responds(to: allAppsSel), let res = workspace.perform(allAppsSel)?.takeUnretainedValue() as? [AnyObject] {
                    rawApps.append(contentsOf: res)
                }
                
                let installedAppsSel = Selector(("allInstalledApplications"))
                if workspace.responds(to: installedAppsSel), let res = workspace.perform(installedAppsSel)?.takeUnretainedValue() as? [AnyObject] {
                    rawApps.append(contentsOf: res)
                }
                
                for app in rawApps {
                    let idSel = Selector(("applicationIdentifier"))
                    let nameSel = Selector(("localizedName"))
                    let typeSel = Selector(("applicationType"))
                    let urlSel = Selector(("bundleURL"))
                    
                    if app.responds(to: idSel) && app.responds(to: nameSel) {
                        if let bundleID = app.perform(idSel)?.takeUnretainedValue() as? String,
                           let localizedName = app.perform(nameSel)?.takeUnretainedValue() as? String {
                            
                            if !bundleID.isEmpty && !localizedName.isEmpty {
                                var appType = "User"
                                if app.responds(to: typeSel), let typeStr = app.perform(typeSel)?.takeUnretainedValue() as? String {
                                    appType = typeStr
                                }
                                
                                var bundleURL: URL? = nil
                                if app.responds(to: urlSel), let url = app.perform(urlSel)?.takeUnretainedValue() as? URL {
                                    bundleURL = url
                                }
                                
                                appsDict[bundleID] = AppItem(
                                    id: bundleID,
                                    name: localizedName,
                                    type: appType,
                                    bundleURL: bundleURL
                                )
                            }
                        }
                    }
                }
            }
            
            let sortedApps = Array(appsDict.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.installedApps = sortedApps
                self.isLoading = false
            }
        }
    }

    func deleteSelectedApps() {
        let selected = installedApps.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        isDeleting = true

        DispatchQueue.global(qos: .userInitiated).async {
            for app in selected {
                // Step 1: Unregister qua LaunchServices API
                if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                    let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
                    let uninstallSel = Selector(("uninstallApplication:withOptions:"))
                    if workspace.responds(to: uninstallSel) {
                        _ = workspace.perform(uninstallSel, with: app.id as NSString, with: nil)
                    }
                }
                
                // Step 2: Xoa thu muc app bang Quyen Root Jailbreak (rm -rf)
                if let bundlePath = app.bundleURL?.path {
                    let rmCommand = "rm -rf \"\(bundlePath)\""
                    _ = runRootCommand(rmCommand)
                    
                    // Step 3: Clear cache SpringBoard bang uicache
                    let uicacheCmd = "uicache -u \"\(bundlePath)\" || uicache -a || /var/jb/usr/bin/uicache -a"
                    _ = runRootCommand(uicacheCmd)
                }
            }
            
            Thread.sleep(forTimeInterval: 1.0)
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
                    Text("Tổng: \(viewModel.installedApps.count) app")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Bỏ chọn") { viewModel.deselectAll() }.foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.top, 5)

                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang tải danh sách...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.installedApps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Không tìm thấy ứng dụng.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredApps) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(app.name).font(.headline)
                                        if app.type == "System" {
                                            Text("System/Root")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.15))
                                                .foregroundColor(.red)
                                                .cornerRadius(4)
                                        }
                                    }
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
                }

                if selectedCount > 0 {
                    Button(action: { viewModel.deleteSelectedApps() }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Xóa \(selectedCount) ứng dụng bằng Root JB")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                    .disabled(viewModel.isDeleting)
                }
            }
            .navigationTitle("Batch Deleter JB")
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
