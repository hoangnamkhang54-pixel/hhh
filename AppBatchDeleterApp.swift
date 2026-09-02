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
    @Published var isLoading: Bool = true

    func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [AppItem] = []
            
            if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
                
                let selectors = ["allInstalledApplications", "allApplications"]
                var rawApps: [AnyObject]? = nil
                
                for selName in selectors {
                    let sel = Selector((selName))
                    if workspace.responds(to: sel) {
                        if let res = workspace.perform(sel)?.takeUnretainedValue() as? [AnyObject] {
                            rawApps = res
                            break
                        }
                    }
                }
                
                if let appList = rawApps {
                    for app in appList {
                        let idSel = Selector(("applicationIdentifier"))
                        let nameSel = Selector(("localizedName"))
                        
                        if app.responds(to: idSel) && app.responds(to: nameSel) {
                            if let bundleID = app.perform(idSel)?.takeUnretainedValue() as? String,
                               let localizedName = app.perform(nameSel)?.takeUnretainedValue() as? String {
                                if !bundleID.isEmpty && !localizedName.isEmpty {
                                    apps.append(AppItem(id: bundleID, name: localizedName))
                                }
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.installedApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.isLoading = false
            }
        }
    }

    func deleteSelectedApps() {
        let selected = installedApps.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        isDeleting = true

        DispatchQueue.global(qos: .userInitiated).async {
            if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                let workspace = workspaceClass.perform(Selector(("defaultWorkspace"))).takeUnretainedValue()
                let uninstallSel = Selector(("uninstallApplication:withOptions:"))
                
                for app in selected {
                    if workspace.responds(to: uninstallSel) {
                        _ = workspace.perform(uninstallSel, with: app.id as NSString, with: nil)
                    }
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
                        Text("Đang quét danh sách ứng dụng...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.installedApps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Không tìm thấy ứng dụng hoặc ứng dụng chưa được cấp quyền Unsandbox qua TrollStore.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                    }
                    .frame(maxHeight: .infinity)
                } else {
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
                }

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
                    .disabled(viewModel.isDeleting)
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
