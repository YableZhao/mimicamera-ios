import SwiftUI

@main
struct MimicameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
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
