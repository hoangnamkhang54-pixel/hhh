import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Text("Batch Deleter")
                .font(.largeTitle)
                .bold()
            Text("Sẵn sàng chạy trên TrollStore!")
                .foregroundColor(.gray)
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
