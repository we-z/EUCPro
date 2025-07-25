import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DragHomeView()
                .tabItem {
                    Label("Drag", systemImage: "gauge.high")
                }
            TrackHomeView()
                .tabItem {
                    Label("Track", systemImage: "map")
                }
            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    RootView()
} 