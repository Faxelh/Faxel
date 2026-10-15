import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

/// Une séance de lecture vidéo (ouverte en plein écran).
struct VideoSession: Identifiable {
    let id = UUID()
    let items: [Track]
    let start: Int
}

/// Lecteur vidéo de Faxel : file de vidéos, vitesse, sous-titres (intégrés,
/// .srt / .vtt à côté de la vidéo ou choisis dans Fichiers), pistes audio,
/// Image dans l'image, reprise là où on s'était arrêté.
final class VideoPlayerModel: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    /// Le lecteur vidéo ouvert (les commandes de l'écran verrouillé lui sont envoyées).
    static weak var active: VideoPlayerModel?

    @Published private(set) var items: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var rate: Float = 1
    @Published var fill = false

    // Sous-titres
    @Published private(set) var externalSubtitles: [URL] = []
    @Published private(set) var embeddedSubtitles: [AVMediaSelectionOption] = []
    @Published private(set) var selectedExternal: URL?
    @Published private(set) var selectedEmbedded: AVMediaSelectionOption?
    @Published private(set) var subtitleText: String?
    @Published var subtitleDelay: Double = 0

    // Pistes audio
    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var selectedAudio: AVMediaSelectionOption?

    @Published private(set) var pipActive = false
    @Published private(set) var pipPossible = false
    @Published var notice: String?
    /// Répéter la vidéo en cours.
    @Published var repeatOne = false
    /// « Épisode suivant » annulé pour cette vidéo.
    @Published var cancelAutoNext = false {
        didSet { if cancelAutoNext { stopCountdown() } }
    }
    /// Compte à rebours « Épisode suivant dans 5, 4, 3, 2, 1 » (en vraies secondes).
    @Published private(set) var nextCountdown: Int?
    private var countdownTimer: Timer?
    /// La vidéo est finie et attend la fin du compte à rebours.
    private var waitingForNext = false
    /// Minuterie : arrêt à cette heure, ou à la fin de la vidéo.
    @Published private(set) var sleepEnd: Date?
    @Published private(set) var sleepAtEnd = false
    /// Appui long : vitesse ×2 tant que le doigt reste posé.
    @Published private(set) var boosted = false
    private var sleepTimer: Timer?

    /// L'Image dans l'image démarre : l'app referme l'écran plein écran pour
    /// laisser voir le reste de l'app (bibliothèque…) derrière la mini-fenêtre.
    var onPictureInPictureStart: (() -> Void)?
    /// On touche la mini-fenêtre : l'app rouvre l'écran plein écran.
    var onPictureInPictureRestore: (() -> Void)?

    let player = AVPlayer()
    private var cues: [SubtitleCue] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var controlObserver: NSKeyValueObservation?
    private var pipObserver: NSKeyValueObservation?
    private var pip: AVPictureInPictureController?
    private var legibleGroup: AVMediaSelectionGroup?
    private var audibleGroup: AVMediaSelectionGroup?
    private var lastSave = Date()
    private var closed = false

    var current: Track? {
        items.indices.contains(index) ? items[index] : nil
    }

    var hasSubtitles: Bool {
        selectedExternal != nil || selectedEmbedded != nil
    }

    override init() {
        super.init()
        player.appliesMediaSelectionCriteriaAutomatically = false
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            self?.tick(time)
        }
        controlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self.isPlaying = status != .paused
                // Vidéo en lecture : l'écran ne se met pas en veille.
                ScreenAwake.set(self.awakeKey, self.isPlaying)
                self.updateNowPlaying()
            }
        }
    }

    /// Chaque lecteur a sa propre raison de garder l'écran allumé (un autre lecteur
    /// qui se ferme ne coupe pas celui qui joue).
    private lazy var awakeKey = "video:\(ObjectIdentifier(self).hashValue)"

    deinit {
        ScreenAwake.set("video:\(ObjectIdentifier(self).hashValue)", false)
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Ouverture

    func open(_ tracks: [Track], start: Int) {
        closed = false
        VideoPlayerModel.active = self
        items = tracks
        index = tracks.indices.contains(start) ? start : 0
        load()
    }

    private func load() {
        guard let track = current else { return }
        stopCountdown()
        cancelAutoNext = false
        boosted = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)

        let item = AVPlayerItem(url: track.fileURL)
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.finished()
        }
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = MediaLibrary.shared.duration(track) ?? 0
        cues = []
        subtitleText = nil
        subtitleDelay = 0
        selectedExternal = nil
        selectedEmbedded = nil
        embeddedSubtitles = []
        audioOptions = []
        selectedAudio = nil
        externalSubtitles = SubtitleParser.siblings(of: track.fileURL)
        let autoSubtitles = UserDefaults.standard.object(forKey: "autoSubtitles") as? Bool ?? true
        if autoSubtitles, let first = externalSubtitles.first {
            selectExternal(first)
        }
        loadSelectionGroups(item.asset, path: track.path)

        if let position = savedPosition(track) {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
            currentTime = position
            notice = L("Reprise à {time}", ["time": Fmt.clock(position)])
        }
        player.play()
        player.rate = rate
        updateNowPlaying()
    }

    private func loadSelectionGroups(_ asset: AVAsset, path: String) {
        Task {
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.current?.path == path else { return }
                self.legibleGroup = legible
                self.audibleGroup = audible
                self.embeddedSubtitles = legible?.options.filter {
                    !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
                } ?? []
                self.audioOptions = (audible?.options.count ?? 0) > 1 ? (audible?.options ?? []) : []
                if let group = audible, let item = self.player.currentItem {
                    self.selectedAudio = item.currentMediaSelection.selectedMediaOption(in: group)
                }
                if let group = legible, let item = self.player.currentItem, self.selectedExternal == nil {
                    // Pas de fichier à côté : sous-titres intégrés dans la langue de l'app, s'il y en a.
                    let auto = UserDefaults.standard.object(forKey: "autoSubtitles") as? Bool ?? true
                    let wanted = self.embeddedSubtitles.first { option in
                        let tag = (option.extendedLanguageTag ?? option.locale?.identifier ?? "").lowercased()
                        return tag.hasPrefix(Lang.code)
                    }
                    if auto, let option = wanted {
                        item.select(option, in: group)
                        self.selectedEmbedded = option
                    } else {
                        item.select(nil, in: group)
                    }
                }
            }
        }
    }

    // MARK: - Commandes

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        // La vidéo reprend la main sur l'écran verrouillé et le Centre de contrôle.
        VideoPlayerModel.active = self
        if player.currentItem == nil {
            load()
            return
        }
        if duration > 0 && currentTime >= duration - 0.3 {
            seek(to: 0)
        }
        player.play()
        player.rate = rate
    }

    func pause() {
        player.pause()
        savePosition()
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.updateNowPlaying() }
        }
        refreshSubtitle()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    var autoNextEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoNextVideo") as? Bool ?? true
    }

    /// Appui long sur la vidéo : ×2, puis retour à la vitesse choisie.
    func setBoost(_ on: Bool) {
        guard on != boosted else { return }
        boosted = on
        if isPlaying || on {
            player.rate = on ? max(2, rate) : rate
        }
    }

    /// Minuterie : 0 = désactivée, -1 = à la fin de la vidéo.
    func setSleep(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEnd = nil
        sleepAtEnd = minutes == -1
        guard minutes > 0 else { return }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepEnd = end
        let timer = Timer(timeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.pause()
            self.sleepEnd = nil
            self.notice = L("Minuterie : lecture arrêtée")
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    /// Image de la vidéo à la position actuelle (capture d'écran).
    func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        guard let track = current else { return completion(nil) }
        let at = currentTime
        DispatchQueue.global(qos: .userInitiated).async {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: track.fileURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try? generator.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: nil)
            DispatchQueue.main.async { completion(image.map { UIImage(cgImage: $0) }) }
        }
    }

    func setRate(_ value: Float) {
        rate = value
        if isPlaying { player.rate = value }
        updateNowPlaying()
    }

    var hasNext: Bool { index + 1 < items.count }

    private var autoNextAllowed: Bool {
        autoNextEnabled && hasNext && !repeatOne && !cancelAutoNext && !sleepAtEnd && duration > 30
    }

    /// Lance le compte à rebours dans les 5 dernières secondes ; l'annule si on recule.
    /// Le compte est mené par une vraie horloge (5, 4, 3, 2, 1) : il ne reste plus jamais
    /// bloqué sur un chiffre quand la vidéo s'arrête un peu avant sa durée annoncée.
    private func updateCountdown() {
        guard autoNextAllowed else {
            stopCountdown()
            return
        }
        guard !waitingForNext else { return }
        let remaining = (duration - currentTime) / Double(max(rate, 0.25))
        if countdownTimer == nil {
            if remaining > 0.05 && remaining <= 5 && isPlaying {
                startCountdown(from: Int(ceil(remaining)))
            }
        } else if remaining > 5.5 {
            // On a reculé dans la vidéo : plus de compte à rebours.
            stopCountdown()
        }
    }

    private func startCountdown(from value: Int) {
        countdownTimer?.invalidate()
        nextCountdown = max(1, min(5, value))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let count = self.nextCountdown else { return }
            if !self.waitingForNext && !self.isPlaying {
                // Vidéo finie sans notification d'AVPlayer : on continue quand même.
                if self.duration > 0 && self.duration - self.currentTime <= 1.5 {
                    self.waitingForNext = true
                } else {
                    return // en pause : le compte attend
                }
            }
            if count > 1 {
                self.nextCountdown = count - 1
            } else {
                self.stopCountdown()
                if self.hasNext && !self.cancelAutoNext { self.next() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        waitingForNext = false
        if nextCountdown != nil { nextCountdown = nil }
    }
    var hasPrevious: Bool { index > 0 }

    func next() {
        guard hasNext else { return }
        savePosition()
        index += 1
        load()
    }

    func previous() {
        if currentTime > 5 || !hasPrevious {
            seek(to: 0)
            return
        }
        savePosition()
        index -= 1
        load()
    }

    private func finished() {
        guard !waitingForNext else { return }
        if repeatOne {
            seek(to: 0)
            player.play()
            player.rate = rate
            return
        }
        forgetPosition()
        if sleepAtEnd {
            sleepAtEnd = false
            isPlaying = false
            notice = L("Minuterie : lecture arrêtée")
            return
        }
        let autoNext = UserDefaults.standard.object(forKey: "autoNextVideo") as? Bool ?? true
        if autoNext && hasNext && !cancelAutoNext {
            if countdownTimer != nil {
                // Le compte à rebours continue (2, 1…) puis l'épisode suivant démarre.
                waitingForNext = true
            } else if duration > 30 {
                waitingForNext = true
                startCountdown(from: 3)
            } else {
                index += 1
                load()
            }
        } else {
            isPlaying = false
        }
    }

    func close() {
        guard !closed else { return }
        stopCountdown()
        closed = true
        dismissedForPiP = false
        savePosition()
        if pip?.isPictureInPictureActive == true {
            pip?.stopPictureInPicture()
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        ScreenAwake.set(awakeKey, false)
        if VideoPlayerModel.active === self {
            VideoPlayerModel.active = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func tick(_ time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite { currentTime = seconds }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0,
           abs(itemDuration - duration) > 0.5 {
            duration = itemDuration
            updateNowPlaying()
        }
        refreshSubtitle()
        updateCountdown()
        if isPlaying && Date().timeIntervalSince(lastSave) > 10 {
            savePosition()
        }
    }

    // MARK: - Sous-titres et pistes

    private func refreshSubtitle() {
        guard selectedExternal != nil, !cues.isEmpty else {
            if subtitleText != nil { subtitleText = nil }
            return
        }
        let text = SubtitleParser.text(at: currentTime - subtitleDelay, in: cues)
        if text != subtitleText { subtitleText = text }
    }

    func selectExternal(_ url: URL) {
        if let group = legibleGroup, let item = player.currentItem {
            item.select(nil, in: group)
        }
        selectedEmbedded = nil
        selectedExternal = url
        let expected = current?.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let parsed = SubtitleParser.load(url)
            DispatchQueue.main.async {
                guard let self = self, self.current?.path == expected, self.selectedExternal == url else { return }
                self.cues = parsed
                if parsed.isEmpty {
                    self.selectedExternal = nil
                    self.notice = L("Ce fichier de sous-titres est vide ou illisible.")
                }
                self.refreshSubtitle()
            }
        }
    }

    func selectEmbedded(_ option: AVMediaSelectionOption) {
        guard let group = legibleGroup, let item = player.currentItem else { return }
        selectedExternal = nil
        cues = []
        subtitleText = nil
        item.select(option, in: group)
        selectedEmbedded = option
    }

    func subtitlesOff() {
        if let group = legibleGroup, let item = player.currentItem {
            item.select(nil, in: group)
        }
        selectedEmbedded = nil
        selectedExternal = nil
        cues = []
        subtitleText = nil
    }

    func selectAudio(_ option: AVMediaSelectionOption) {
        guard let group = audibleGroup, let item = player.currentItem else { return }
        item.select(option, in: group)
        selectedAudio = option
    }

    /// Fichier .srt / .vtt choisi dans l'app Fichiers : copié à côté de la vidéo
    /// (il sera retrouvé tout seul la prochaine fois).
    func importSubtitle(_ url: URL) {
        guard let track = current else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.lowercased()
        guard subtitleExtensions.contains(ext) else {
            notice = L("Choisissez un fichier .srt, .vtt, .ass ou .ssa.")
            return
        }
        let base = track.fileURL.deletingPathExtension()
        var target = base.appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = URL(fileURLWithPath: base.path + ".\(number)." + ext)
            number += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            target = url
        }
        externalSubtitles = SubtitleParser.siblings(of: track.fileURL)
        if target != url && !externalSubtitles.contains(target) {
            externalSubtitles.append(target)
        }
        selectExternal(target)
        notice = L("Sous-titres chargés.")
    }

    static func optionName(_ option: AVMediaSelectionOption) -> String {
        let name = option.displayName
        return name.isEmpty ? (option.extendedLanguageTag ?? L("Piste")) : name
    }

    // MARK: - Reprise de la lecture

    private static let positionsKey = "videoPositions"

    private func savedPosition(_ track: Track) -> Double? {
        let positions = UserDefaults.standard.dictionary(forKey: VideoPlayerModel.positionsKey) as? [String: Double]
        guard let value = positions?[track.path], value > 5 else { return nil }
        return value
    }

    func savePosition() {
        lastSave = Date()
        guard let track = current, duration > 60 else { return }
        var positions = UserDefaults.standard.dictionary(forKey: VideoPlayerModel.positionsKey) as? [String: Double] ?? [:]
        if currentTime > 10 && currentTime < duration - 15 {
            positions[track.path] = currentTime
        } else {
            positions.removeValue(forKey: track.path)
        }
        if positions.count > 300 {
            positions = Dictionary(uniqueKeysWithValues: positions.prefix(200).map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(positions, forKey: VideoPlayerModel.positionsKey)
    }

    private func forgetPosition() {
        guard let track = current else { return }
        var positions = UserDefaults.standard.dictionary(forKey: VideoPlayerModel.positionsKey) as? [String: Double] ?? [:]
        positions.removeValue(forKey: track.path)
        UserDefaults.standard.set(positions, forKey: VideoPlayerModel.positionsKey)
    }

    // MARK: - Image dans l'image

    /// Surface affichée en ce moment (l'Image dans l'image s'y rattache).
    private weak var inlineLayer: AVPlayerLayer?
    /// L'Image dans l'image a été lancée avec le bouton (et non en quittant l'app).
    private var userStartedPiP = false
    /// L'écran plein écran a été refermé pour laisser voir l'app derrière la mini-fenêtre.
    private var dismissedForPiP = false

    func attach(_ layer: AVPlayerLayer) {
        inlineLayer = layer
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let current = pip {
            // Déjà relié à cette surface, ou la mini-fenêtre est ouverte : on rattache plus tard.
            if current.playerLayer === layer || current.isPictureInPictureActive { return }
        }
        pipObserver = nil
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        pip = controller
        pipObserver = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            let possible = pip.isPictureInPicturePossible
            DispatchQueue.main.async { self?.pipPossible = possible }
        }
    }

    func togglePictureInPicture() {
        guard let pip = pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            userStartedPiP = true
            pip.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        pipActive = true
        // Bouton touché dans l'app : on referme le plein écran pour voir l'app derrière.
        // En quittant l'app (lancement automatique), on garde l'écran tel quel pour le retour.
        if userStartedPiP && UIApplication.shared.applicationState == .active {
            dismissedForPiP = true
            onPictureInPictureStart?()
        }
        userStartedPiP = false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        userStartedPiP = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        pipActive = false
        if dismissedForPiP {
            // Mini-fenêtre fermée avec la croix : la vidéo s'arrête vraiment.
            dismissedForPiP = false
            close()
            return
        }
        // Rattache l'Image dans l'image à la surface affichée (sinon elle ne se relance plus).
        if let layer = inlineLayer, pip?.playerLayer !== layer {
            attach(layer)
        }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        if dismissedForPiP {
            dismissedForPiP = false
            onPictureInPictureRestore?()
        }
        completionHandler(true)
    }

    // MARK: - Écran verrouillé

    func updateNowPlaying() {
        guard VideoPlayerModel.active === self, let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: MediaLibrary.shared.title(track),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if !track.uploader.isEmpty {
            info[MPMediaItemPropertyArtist] = track.uploader
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

/// Luminosité de l'écran et volume (gestes du lecteur vidéo).
enum DeviceControls {
    static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    static var brightness: CGFloat {
        get { screen?.brightness ?? 0.5 }
        set { screen?.brightness = min(1, max(0, newValue)) }
    }

    /// Vue du volume d'iOS (invisible) : son curseur règle le volume du téléphone.
    static weak var volumeView: MPVolumeView?

    /// Le curseur est créé par iOS un peu après l'affichage : on le cherche à chaque fois.
    static var volumeSlider: UISlider? {
        func find(_ view: UIView) -> UISlider? {
            if let slider = view as? UISlider { return slider }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return volumeView.flatMap { find($0) }
    }

    /// Dernière valeur demandée (le curseur d'iOS met un instant à suivre).
    private static var wanted: Float?

    static var volume: Float {
        get { wanted ?? volumeSlider?.value ?? AVAudioSession.sharedInstance().outputVolume }
        set {
            let value = min(1, max(0, newValue))
            wanted = value
            if let slider = volumeSlider {
                // Volume du téléphone (comme les boutons latéraux).
                slider.setValue(value, animated: false)
                slider.sendActions(for: .valueChanged)
                slider.sendActions(for: .touchUpInside)
                VideoPlayerModel.active?.player.volume = 1
            } else {
                // Secours : volume de la vidéo elle-même.
                VideoPlayerModel.active?.player.volume = value
            }
        }
    }

    /// Fin du geste : on relit le vrai volume au prochain geste.
    static func endVolumeGesture() {
        wanted = nil
    }
}

/// Réglage du volume système sans afficher le bandeau d'iOS.
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        // Presque invisible mais bien « affichée » : sinon iOS ignore les changements de volume
        // et montre son propre bandeau.
        view.alpha = 0.011
        view.isUserInteractionEnabled = false
        DeviceControls.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        DeviceControls.volumeView = uiView
    }
}

/// Surface d'affichage de la vidéo (AVPlayerLayer).
final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}

struct VideoSurface: UIViewRepresentable {
    let video: VideoPlayerModel
    let fill: Bool

    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.backgroundColor = .black
        view.playerLayer.player = video.player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        video.attach(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerSurface, context: Context) {
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
    }
}
