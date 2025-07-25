import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            StartView()
                .tabItem {
                    Label("Start", systemImage: "flag.checkered")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}

#Preview {
    RootView()
} 