import UIKit

/// Garde l'écran allumé tant qu'une raison existe : vidéo en lecture (lecteur de Faxel
/// ou navigateur : reels, YouTube…), téléchargements, transfert Wi-Fi.
///
/// L'état est réaffirmé toutes les 3 s : iOS (plein écran vidéo d'une page, retour
/// d'arrière-plan…) remet parfois la mise en veille sans prévenir. Les raisons venues
/// des pages web expirent si la page ne donne plus de nouvelles (onglet planté, fermé…).
enum ScreenAwake {
    /// Raison → date d'expiration (nil : jusqu'à ce qu'on la retire).
    private static var reasons: [String: Date?] = [:]
    private static var timer: Timer?
    private static var observing = false

    static func set(_ reason: String, _ on: Bool, ttl: TimeInterval? = nil) {
        perform {
            if on {
                reasons[reason] = ttl.map { Date().addingTimeInterval($0) }
            } else {
                reasons.removeValue(forKey: reason)
            }
            apply()
        }
    }

    /// Retire toutes les raisons qui commencent par `prefix` (ex. un onglet fermé).
    static func clear(prefix: String) {
        perform {
            reasons = reasons.filter { !$0.key.hasPrefix(prefix) }
            apply()
        }
    }

    private static func perform(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private static func apply() {
        let now = Date()
        reasons = reasons.filter { _, expiry in expiry.map { $0 > now } ?? true }
        let wanted = !reasons.isEmpty
        // Toujours réécrit (pas seulement au changement) : iOS peut l'avoir remis à false.
        if wanted || UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.isIdleTimerDisabled = wanted
        }
        if wanted && timer == nil {
            let repeating = Timer(timeInterval: 3, repeats: true) { _ in apply() }
            RunLoop.main.add(repeating, forMode: .common)
            timer = repeating
        } else if !wanted {
            timer?.invalidate()
            timer = nil
        }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { _ in apply() }
        }
    }
}
