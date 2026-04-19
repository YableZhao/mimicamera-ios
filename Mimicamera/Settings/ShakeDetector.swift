import SwiftUI
import UIKit

/// Posts a notification when the user shakes the device. SwiftUI does not
/// expose `motionEnded`, so we piggy-back on UIWindow via a UIApplication
/// extension and re-emit via NotificationCenter.
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("MimicameraDeviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

struct ShakeModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(_ action: @escaping () -> Void) -> some View {
        modifier(ShakeModifier(action: action))
    }
}
