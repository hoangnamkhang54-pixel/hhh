import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                Text("TrollStore Batch Deleter")
                    .font(.title)
                    .bold()
                Text("Ứng dụng hỗ trợ quản lý và xóa nhanh các gói ứng dụng trên iOS.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                Spacer()
            }
            .padding()
            .navigationTitle("Batch Deleter")
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
