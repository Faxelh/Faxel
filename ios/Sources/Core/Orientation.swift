import UIKit

/// Délégué de l'app : décide des orientations permises
/// (portrait partout, paysage dans le lecteur vidéo).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }
}

/// Rotation de l'écran (portrait / paysage) pour le lecteur vidéo.
enum Orientation {
    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    static var isLandscape: Bool {
        scene?.interfaceOrientation.isLandscape ?? false
    }

    /// Orientations permises (ex. .allButUpsideDown dans le lecteur).
    static func allow(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationMask = mask
        refresh()
    }

    /// Tourne l'écran vers l'orientation voulue.
    static func rotate(to mask: UIInterfaceOrientationMask) {
        guard let scene = scene else { return }
        if !AppDelegate.orientationMask.contains(mask) {
            AppDelegate.orientationMask = mask
        }
        refresh()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    /// Bloque la rotation sur l'orientation actuelle.
    static func lockCurrent() {
        allow(isLandscape ? currentLandscape : .portrait)
    }

    private static var currentLandscape: UIInterfaceOrientationMask {
        scene?.interfaceOrientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
    }

    private static func refresh() {
        guard let scene = scene else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }
}
