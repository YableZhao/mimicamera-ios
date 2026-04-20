import SwiftUI

/// Top-level two-tab surface. `Edit` is the new library-first flow (commit 3+);
/// `Shoot` is the existing live-camera experience. Both tabs share a single
/// `StyleStore` injected at the App level, so picking a look in one tab
/// immediately shows up in the other.
struct RootView: View {
    @State private var selection: Tab = .shoot

    enum Tab: Hashable { case edit, shoot }

    var body: some View {
        TabView(selection: $selection) {
            EditorTabView()
                .tabItem { Label("Edit", systemImage: "photo.stack") }
                .tag(Tab.edit)

            CameraTabView()
                .tabItem { Label("Shoot", systemImage: "camera") }
                .tag(Tab.shoot)
        }
        .tint(Color(red: 0.82, green: 0.29, blue: 0.23))
    }
}
