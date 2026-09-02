import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Text("App Batch Deleter")
                .font(.largeTitle)
                .bold()
            Text("Ứng dụng đã sẵn sàng trên TrollStore!")
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
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
