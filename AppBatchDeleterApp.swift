import SwiftUI
import Foundation
import Darwin
import UserNotifications

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let bundleURL: URL?
    var isSelected: Bool = false
}

func elevateToRoot() {
    setuid(0)
    setgid(0)
}

func isFilzaInstalled() -> Bool {
    let possibleFilzaPaths = [
        "/Applications/Filza.app",
        "/var/jb/Applications/Filza.app",
        "/var/mobile/Applications/Filza.app",
        "/var/containers/Bundle/Application/Filza.app"
    ]
    for path in possibleFilzaPaths {
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
    }
    if let url = URL(string: "filza://"), UIApplication.shared.canOpenURL(url) {
        return true
    }
    return false
}

func openInFilza(path: String) {
    let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    if let url = URL(string: "filza://view\(encodedPath)") {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

func removePathRecursively(_ path: String) {
    elevateToRoot()
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
        if isDir.boolValue {
            if let subItems = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for item in subItems {
                    let subPath = (path as NSString).appendingPathComponent(item)
                    removePathRecursively(subPath)
                }
            }
            _ = rmdir(path)
        } else {
            _ = unlink(path)
        }
    }
}

func findAllContainerPaths(for bundleID: String) -> [String] {
    var paths: [String] = []
    let containerBases = [
        "/var/mobile/Containers/Data/Application",
        "/var/mobile/Containers/Shared/AppGroup",
        "/var/mobile/Containers/Data/PluginKitPlugin"
    ]
    
    for base in containerBases {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
        for sub in subdirs {
            let fullFolder = "\(base)/\(sub)"
            let metadataPath = "\(fullFolder)/.com.apple.mobile_container_manager.metadata.plist"
            if FileManager.default.fileExists(atPath: metadataPath),
               let dict = NSDictionary(contentsOfFile: metadataPath),
               let identifier = dict["MCMMetadataIdentifier"] as? String,
               identifier == bundleID {
                paths.append(fullFolder)
            }
        }
    }
    return paths
}

func findBinary(_ name: String) -> String? {
    let candidates = [
        "/var/jb/usr/bin/\(name)",
        "/usr/bin/\(name)",
        "/var/jb/bin/\(name)",
        "/bin/\(name)",
        "/Applications/TrollStore.app/\(name)",
        "/var/containers/Bundle/Application/TrollStore.app/\(name)",
        "/var/apps/TrollStore.app/\(name)"
    ]
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return nil
}

func runBinary(_ path: String, args: [String]) -> Int32 {
    elevateToRoot()
    var pid: pid_t = 0
    var cArgs = [strdup(path)] + args.map { strdup($0) } + [nil]
    defer {
        for ptr in cArgs where ptr != nil { free(ptr) }
    }
    let status = posix_spawn(&pid, path, nil, nil, &cArgs, nil)
    if status == 0 {
        var exitStatus: Int32 = 0
        waitpid(pid, &exitStatus, 0)
        return exitStatus
    }
    return status
}

func uninstallAppCompletely(app: AppItem) {
    elevateToRoot()

    // 1. Dùng trollstorehelper xóa chính thức để gỡ đăng ký khỏi hệ thống
    if let tsPath = findBinary("trollstorehelper") {
        _ = runBinary(tsPath, args: ["delete", app.id])
    }

    // 2. Xóa tất cả các thùng chứa dữ liệu Data Containers, App Groups, Plugins
    let containerPaths = findAllContainerPaths(for: app.id)
    for cPath in containerPaths {
        removePathRecursively(cPath)
    }

    // 3. Xóa thư mục Bundle nếu còn sót
    if let bundlePath = app.bundleURL?.path {
        removePathRecursively(bundlePath)
    }

    // 4. Xóa Preferences & Caches của app
    removePathRecursively("/var/mobile/Library/Preferences/\(app.id).plist")
    removePathRecursively("/var/mobile/Library/Caches/\(app.id)")
    removePathRecursively("/var/mobile/Library/Saved Application State/\(app.id).savedState")

    // 5. Làm mới lại bộ nhớ đệm Icon Cache (uicache)
    if let uicachePath = findBinary("uicache") {
        _ = runBinary(uicachePath, args: ["-u", app.id])
        _ = runBinary(uicachePath, args: ["-a"])
    }
}

func sendLocalNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
}

class AppManagerViewModel: ObservableObject {
    @Published var installedApps: [AppItem] = []
    @Published var searchText: String = ""
    @Published var isDeleting: Bool = false
    @Published var statusText: String = ""
    @Published var isLoading: Bool = true
    @Published var showFilzaAlert: Bool = false
    @Published var showNotificationPermissionAlert: Bool = false

    func checkFilzaStatus() {
        if !isFilzaInstalled() {
            showFilzaAlert = true
        }
    }

    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

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
                            
                            if !bundleID.isEmpty && !localizedName.isEmpty && bundleID != "com.hoangnamkhang.AppBatchDeleter" {
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

    func startBatchDeleteProcess() {
        if !isFilzaInstalled() {
            showFilzaAlert = true
        }

        requestNotificationPermission { granted in
            if !granted {
                self.showNotificationPermissionAlert = true
            }
            self.executeBackgroundDeletion()
        }
    }

    private func executeBackgroundDeletion() {
        let selected = installedApps.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        DispatchQueue.main.async {
            self.isDeleting = true
            self.statusText = "Đang chuẩn bị..."
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "FilzaBatchDeleteTask") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var deletedCount = 0
            let total = selected.count

            for (index, app) in selected.enumerated() {
                DispatchQueue.main.async {
                    self.statusText = "Đang xóa (\(index + 1)/\(total)): \(app.name)"
                }
                
                uninstallAppCompletely(app: app)
                deletedCount += 1
            }

            if let uicachePath = findBinary("uicache") {
                _ = runBinary(uicachePath, args: ["-a"])
            }

            sendLocalNotification(
                title: "Dọn dẹp hoàn tất",
                body: "Đã xóa hoàn toàn \(deletedCount) ứng dụng và dọn dẹp toàn bộ dữ liệu, cache hệ thống."
            )

            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }

            DispatchQueue.main.async {
                self.isDeleting = false
                self.statusText = ""
                self.loadApps()
            }
        }
    }

    func selectAll() {
        for i in 0..<installedApps.count { installedApps[i].isSelected = true }
    }

    func deselectAll() {
        for i in 0..<installedApps.count { installedApps[i].isSelected = false }
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
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
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
                        Text("Đang nạp danh sách...")
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
                                            Text("System")
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
                                
                                Button(action: {
                                    let containers = findAllContainerPaths(for: app.id)
                                    if let firstContainer = containers.first {
                                        openInFilza(path: firstContainer)
                                    } else if let bundlePath = app.bundleURL?.path {
                                        openInFilza(path: bundlePath)
                                    }
                                }) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                        .padding(.trailing, 4)
                                }
                                .buttonStyle(BorderedButtonStyle())

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
                    VStack(spacing: 6) {
                        if viewModel.isDeleting {
                            Text(viewModel.statusText)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Button(action: { viewModel.startBatchDeleteProcess() }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text(viewModel.isDeleting ? "Đang xử lý dọn dẹp..." : "Xóa \(selectedCount) ứng dụng")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isDeleting ? Color.gray : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isDeleting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Filza Batch Deleter")
            .onAppear {
                viewModel.checkFilzaStatus()
                viewModel.loadApps()
            }
            .alert(isPresented: $viewModel.showFilzaAlert) {
                Alert(
                    title: Text("Cảnh báo Filza"),
                    message: Text("Yêu cầu thiết bị cài đặt Filza File Manager để quản lý mở trực tiếp thư mục dữ liệu."),
                    dismissButton: .default(Text("Đã hiểu"))
                )
            }
            .alert(isPresented: $viewModel.showNotificationPermissionAlert) {
                Alert(
                    title: Text("Cấp quyền thông báo"),
                    message: Text("Vui lòng cho phép ứng dụng gửi thông báo khi hoàn thành tiến trình dọn dẹp ngầm."),
                    dismissButton: .default(Text("Tiếp tục"))
                )
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct AppBatchDeleterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
