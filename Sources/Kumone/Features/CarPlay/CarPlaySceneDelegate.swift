#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// Entry point for CarPlay scene lifecycle management.
@objc(CarPlaySceneDelegate)
public final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    public var interfaceController: CPInterfaceController?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        CarPlayManager.shared.attach(interfaceController: interfaceController, window: window)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        CarPlayManager.shared.detach()
    }
}
#endif
