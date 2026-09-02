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
    
    func deleteApps(bundleIDs: [String]) {
        guard !bundleIDs.isEmpty else { return }
        isDeleting = true
        statusMessage = "Đang tiến hành xóa..."
        DispatchQueue.global(qos: .userInitiated).async {
            for bundleID in bundleIDs {
                self.uninstallApp(bundleID: bundleID)
            }
            DispatchQueue.main.async {
                self.isDeleting = false
                self.statusMessage = "Đã xóa xong các ứng dụng đã chọn!"
                self.loadApps()
            }
        }
    }
    
    private func uninstallApp(bundleID: String) {
        let handle = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_NOW)
        typealias MobileInstallationUninstallFn = @convention(c) (String, NSDictionary, OpaquePointer?) -> Bool
        if let symbol = dlsym(handle, "MobileInstallationUninstall") {
            let uninstall = unsafeBitCast(symbol, to: MobileInstallationUninstallFn.self)
            let _ = uninstall(bundleID, ["SignerIdentity": "TrollStore"] as NSDictionary, nil)
        }
        let _ = system("uicache -p")
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppManagerViewModel()
    @State private var searchText = ""
    @State private var showConfirmAlert = false

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.installedApps.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang quét danh sách ứng dụng...")
                            .foregroundColor(.gray)
                    }
                    .onAppear {
                        viewModel.loadApps()
                    }
                } else {
                    List {
                        Section(header: Text("Danh sách ứng dụng người dùng (\(viewModel.installedApps.count))")) {
                            ForEach($viewModel.installedApps) { $app in
                                if searchText.isEmpty || app.name.wrappedValue.localizedCaseInsensitiveContains(searchText) || app.id.wrappedValue.localizedCaseInsensitiveContains(searchText) {
                                    Button(action: {
                                        app.isSelected.toggle()
                                    }) {
                                        HStack {
                                            Image(systemName: app.isSelected.wrappedValue ? "checkmark.square.fill" : "square")
                                                .foregroundColor(app.isSelected.wrappedValue ? .blue : .gray)
                                                .font(.system(size: 20))
                                            VStack(alignment: .leading, spacing: 4) {
                                            Text(app.name.wrappedValue)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(app.id.wrappedValue)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Tìm kiếm ứng dụng...")
            .listStyle(InsetGroupedListStyle())
            
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: {
                        let allSelected = viewModel.installedApps.allSatisfy { $0.isSelected }
                        for i in 0..<viewModel.installedApps.count {
                            viewModel.installedApps[i].isSelected = !allSelected
                        }
                    }) {
                        Text("Chọn tất cả")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        showConfirmAlert = true
                    }) {
                        Text("Xóa đã chọn (\(viewModel.installedApps.filter({ $0.isSelected }).count))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.installedApps.contains(where: { $0.isSelected }) ? Color.red : Color.gray.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!viewModel.installedApps.contains(where: { $0.isSelected }) || viewModel.isDeleting)
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
    .navigationTitle("TrollStore Batch Delete")
    .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                viewModel.loadApps()
            }) {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
    .alert(isPresented: $showConfirmAlert) {
        Alert(
            title: Text("Xác nhận xóa"),
            message: Text("Bạn có chắc chắn muốn gỡ cài đặt các ứng dụng đã chọn không?"),
            primaryButton: .destructive(Text("Xóa")) {
                let selectedIDs = viewModel.installedApps.filter { $0.isSelected }.map { $0.id }
                viewModel.deleteApps(bundleIDs: selectedIDs)
            },
            secondaryButton: .cancel(Text("Hủy"))
        )
      }
    }
  }
}
