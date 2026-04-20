import SwiftUI

@main
struct MimicameraApp: App {
    @State private var style = StyleStore()
    @State private var recents = RecentEditsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(style)
                .environment(recents)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "mimicamera", url.host == "fit" else { return }
                    NotificationCenter.default.post(
                        name: SharedContainer.sharedImageReadyNotification,
                        object: nil
                    )
                }
        }
    }
}
