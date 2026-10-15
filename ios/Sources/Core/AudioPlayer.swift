import Accelerate
import AVFoundation
import MediaPlayer
import UIKit

/// Temps de lecture (observé seulement par les barres de progression).
final class PlaybackClock: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
}

/// Spectre du son (observé seulement par les visualiseurs du lecteur plein écran).
final class SpectrumMeter: ObservableObject {
    @Published var spectrum: [Float] = Array(repeating: 0, count: AudioPlayer.bandCount)

    var bass: Float {
        let low = spectrum.prefix(5)
        return low.isEmpty ? 0 : low.reduce(0, +) / Float(low.count)
    }
}

/// Lecteur audio de Faxel, construit sur AVAudioEngine : égaliseur 10 bandes,
/// vitesse, spectre en temps réel (visualiseur), file de lecture, aléatoire,
/// répétition, lecture en arrière-plan, commandes de l'écran verrouillé et minuteur.
final class AudioPlayer: NSObject, ObservableObject {
    enum RepeatMode: String {
        case off, all, one
    }

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    /// Temps et spectre vivent à part : seuls la barre de progression et les
    /// visualiseurs se redessinent souvent, pas toute l'app (navigation fluide).
    let clock = PlaybackClock()
    let meter = SpectrumMeter()

    private(set) var currentTime: Double {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }

    private(set) var duration: Double {
        get { clock.duration }
        set { if clock.duration != newValue { clock.duration = newValue } }
    }
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var sleepEnd: Date?
    @Published private(set) var rate: Float = 1
    @Published private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentlyPlayed") ?? []

    // Égaliseur
    static let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    @Published private(set) var eqEnabled = UserDefaults.standard.bool(forKey: "eqEnabled")
    @Published private(set) var eqGains: [Float] = AudioPlayer.savedGains()
    @Published private(set) var eqPreset = UserDefaults.standard.string(forKey: "eqPreset") ?? "flat"

    // Visualiseur : 0…1 par bande
    private(set) var spectrum: [Float] {
        get { meter.spectrum }
        set { meter.spectrum = newValue }
    }
    static let bandCount = 32
    /// Le lecteur plein écran est affiché : on calcule le spectre.
    var spectrumWanted = false {
        didSet { updateTap() }
    }

    static let presets: [(id: String, name: String, gains: [Float])] = [
        ("flat", "Neutre", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("bass", "Basses+", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        ("superbass", "Super basses", [9, 8, 6, 3, 0, -1, -1, 0, 0, 0]),
        ("treble", "Aigus+", [0, 0, 0, 0, 0, 1, 3, 4, 5, 6]),
        ("vocal", "Voix", [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        ("pop", "Pop", [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2]),
        ("rock", "Rock", [5, 4, 2, -1, -2, -1, 2, 3, 4, 4]),
        ("hiphop", "Hip-hop", [6, 5, 2, 3, -1, -1, 1, 0, 2, 3]),
        ("electro", "Électro", [5, 4, 1, 0, -2, 2, 1, 2, 4, 5]),
        ("jazz", "Jazz", [3, 2, 1, 2, -2, -2, 0, 1, 3, 3]),
        ("classical", "Classique", [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
        ("acoustic", "Acoustique", [4, 3, 2, 1, 1, 1, 2, 3, 2, 2]),
        ("night", "Nuit (doux)", [-2, -1, 0, 1, 1, 1, 0, -2, -4, -5]),
    ]

    var onMessage: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var startFrame: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var generation = 0
    private var original: [Track] = []
    private var ticker: Timer?
    private var recoveryFailures = 0
    /// Le moteur doit être relancé proprement à la prochaine lecture (app passée en arrière-plan,
    /// interruption…) : iOS peut le laisser « en marche » sans plus produire de son.
    private var needsRestart = false
    /// Fondu doux à la pause et à la reprise (pas de « clic », pas de coupure sèche).
    private var fadeTimer: Timer?
    private var fadeToken = 0
    private var fadeStep = 0
    private var sleepTimer: Timer?
    /// La musique jouait quand un appel (ou une alarme) l'a coupée.
    private var resumeAfterInterruption = false
    private var tapInstalled = false
    private let analyzer = SpectrumAnalyzer(bands: AudioPlayer.bandCount)
    private var lastSpectrum = Date.distantPast
    private var artwork: MPMediaItemArtwork?
    private var artworkKey: String?

    var current: Track? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    override init() {
        super.init()
        engine.attach(node)
        engine.attach(pitch)
        engine.attach(equalizer)
        connectChain(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        configureEqualizer()
        configureRemoteCommands()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interrupted(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(configurationChanged(_:)),
                           name: .AVAudioEngineConfigurationChange, object: engine)
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            AudioLog.add("App en arrière-plan · lecture=\(self.isPlaying) · moteur=\(self.engine.isRunning) · t=\(Int(self.isPlaying ? self.position() : self.pausedTime))s")
            if !self.isPlaying { self.needsRestart = true }
            self.saveState()
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            AudioLog.add("App au premier plan · lecture=\(self.isPlaying) · moteur=\(self.engine.isRunning) · t=\(Int(self.isPlaying ? self.position() : self.pausedTime))s")
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            AudioLog.add("Services audio d'iOS réinitialisés")
            self.needsRestart = true
            if self.isPlaying {
                self.pause()
                self.resume()
            }
        }
        if let saved = UserDefaults.standard.string(forKey: "repeatMode"), let mode = RepeatMode(rawValue: saved) {
            repeatMode = mode
        }
        center.addObserver(forName: CoverEditor.changed, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let track = self.current, note.object as? String == track.path else { return }
            self.artworkKey = nil
            self.loadArtwork(for: track)
        }
    }

    /// Appel téléphonique, alarme… : pause puis reprise si iOS le permet.
    @objc private func interrupted(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async {
            let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).map { String($0) } ?? "-"
            AudioLog.add("Interruption \(type == .began ? "début" : "fin") · raison=\(reason) · lecture=\(self.isPlaying)")
            if type == .began {
                self.needsRestart = true
                // iOS envoie aussi « début d'interruption » quand l'app était simplement suspendue
                // (musique en pause, app quittée) : ce n'est pas un appel, on ne touche à rien.
                if let reasonRaw = info[AVAudioSessionInterruptionReasonKey] as? UInt,
                   AVAudioSession.InterruptionReason(rawValue: reasonRaw) == .appWasSuspended {
                    return
                }
                self.resumeAfterInterruption = self.isPlaying
                if self.isPlaying { self.pause() }
            } else {
                let options = AVAudioSession.InterruptionOptions(
                    rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                // On ne relance que si la musique jouait avant l'appel (pas si vous l'aviez mise en pause).
                if options.contains(.shouldResume) && self.resumeAfterInterruption && self.current != nil {
                    self.resume()
                }
                self.resumeAfterInterruption = false
            }
        }
    }

    /// Écouteurs débranchés : pause, comme dans Musique.
    @objc private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        DispatchQueue.main.async {
            AudioLog.add("Écouteurs débranchés")
            if self.isPlaying { self.pause() }
        }
    }

    /// Changement de sortie (casque, Bluetooth…) : le moteur s'arrête, on le relance au même endroit.
    @objc private func configurationChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            // iOS envoie aussi cette notification quand le moteur vient d'être (re)démarré :
            // si tout tourne, on ne touche à rien (sinon le bouton lecture/pause clignote).
            guard self.file != nil else { return }
            AudioLog.add("Configuration audio changée · moteur=\(self.engine.isRunning) · nœud=\(self.node.isPlaying) · lecture=\(self.isPlaying)")
            // Le lecteur a pu perdre son morceau : il sera reprogrammé à la prochaine lecture.
            self.needsRestart = true
            // Tout tourne (cas d'un redémarrage) : rien à faire, sinon on boucle.
            if self.engine.isRunning && (self.node.isPlaying || !self.isPlaying) { return }
            self.recoverEngine(resume: self.isPlaying)
        }
    }

    /// Le moteur a été arrêté par iOS (casque, Bluetooth, app en arrière-plan…) :
    /// on le relance au même endroit, sans recharger le morceau ni changer l'état lecture/pause.
    private func recoverEngine(resume: Bool) {
        guard let file = file else { return }
        AudioLog.add("Moteur arrêté par iOS · reprise=\(resume) · t=\(Int(resume ? currentTime : pausedTime))s")
        let time = resume ? currentTime : pausedTime
        schedule(from: AVAudioFramePosition(time * file.processingFormat.sampleRate))
        pausedTime = time
        currentTime = time
        guard resume else {
            updateNowPlaying()
            return
        }
        cancelFade()
        activateSession()
        if startEngine() {
            node.play()
            recoveryFailures = 0
            updateNowPlaying()
        } else {
            recoveryFailures += 1
            if recoveryFailures >= 3 {
                recoveryFailures = 0
                isPlaying = false
                stopClock()
                updateNowPlaying()
                saveState()
            }
        }
    }

    // MARK: - File d'attente

    /// « Lire ensuite » : juste après le morceau en cours.
    func playNext(_ track: Track) {
        guard track.exists else { return }
        if queue.isEmpty {
            play([track])
            return
        }
        queue.insert(track, at: min(index + 1, queue.count))
        original.append(track)
        saveState()
    }

    /// « Ajouter à la file » : à la fin.
    func addToQueue(_ track: Track) {
        guard track.exists else { return }
        if queue.isEmpty {
            play([track])
            return
        }
        queue.append(track)
        original.append(track)
        saveState()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let now = current
        for offset in offsets.sorted(by: >) where offset != index && queue.indices.contains(offset) {
            queue.remove(at: offset)
        }
        index = queue.firstIndex(where: { $0.id == now?.id }) ?? 0
        saveState()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        let now = current
        queue.move(fromOffsets: source, toOffset: destination)
        index = queue.firstIndex(where: { $0.id == now?.id }) ?? 0
        saveState()
    }

    func jump(to offset: Int) {
        guard queue.indices.contains(offset) else { return }
        index = offset
        load(play: true)
    }

    func setRate(_ value: Float) {
        rate = value
        pitch.rate = value
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: position() + seconds)
    }

    // MARK: - Lecture

    func play(_ tracks: [Track], start: Int = 0, shuffled: Bool = false) {
        let playable = tracks.filter { $0.exists }
        guard !playable.isEmpty else {
            onMessage?(L("Fichier introuvable (supprimé ou déplacé)."))
            return
        }
        var startTrack = tracks.indices.contains(start) ? tracks[start] : playable[0]
        if !startTrack.exists { startTrack = playable[0] }
        original = playable
        shuffle = shuffled
        if shuffled {
            var rest = playable.filter { $0.id != startTrack.id }
            rest.shuffle()
            queue = [startTrack] + rest
        } else {
            queue = playable
        }
        index = queue.firstIndex(where: { $0.id == startTrack.id }) ?? 0
        load(play: true)
    }

    func toggleShuffle() {
        guard let now = current else {
            shuffle.toggle()
            return
        }
        shuffle.toggle()
        if shuffle {
            var rest = original.filter { $0.id != now.id }
            rest.shuffle()
            queue = [now] + rest
            index = 0
        } else {
            queue = original
            index = queue.firstIndex(where: { $0.id == now.id }) ?? 0
        }
        saveState()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    func toggle() {
        if isPlaying && engine.isRunning { pause() } else { resume() }
    }

    /// La musique démarre : une vidéo restée ouverte (en pause, en arrière-plan) ne doit plus
    /// recevoir les commandes de l'écran verrouillé et du Centre de contrôle.
    private func takeOverFromVideo() {
        guard let video = VideoPlayerModel.active else { return }
        if video.isPlaying { video.pause() }
        VideoPlayerModel.active = nil
    }

    func resume() {
        guard current != nil else { return }
        takeOverFromVideo()
        guard file != nil else {
            load(play: true, at: pausedTime)
            return
        }
        // Déjà « en lecture » (moteur coupé par iOS) : on repart de la dernière position lue.
        if isPlaying { pausedTime = currentTime }
        AudioLog.add("Lecture demandée · t=\(Int(pausedTime))s · moteur=\(engine.isRunning) · relance=\(needsRestart) · app=\(appStateName())")
        guard activateSession() else {
            // iOS refuse parfois la première demande (app réveillée par l'écran verrouillé) : on réessaie.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self, !self.isPlaying, self.activateSession() else { return }
                self.startPlayback()
            }
            return
        }
        startPlayback()
    }

    /// Démarre le son depuis pausedTime. Après un passage en arrière-plan, le moteur est
    /// toujours arrêté puis relancé : iOS peut le dire « en marche » alors qu'il ne joue plus rien.
    private func startPlayback() {
        guard let file = file else { return }
        let background = UIApplication.shared.applicationState != .active
        if needsRestart || background || !engine.isRunning {
            engine.stop()
            schedule(from: AVAudioFramePosition(pausedTime * file.processingFormat.sampleRate))
            needsRestart = false
        }
        guard startEngine() else {
            // Dernier recours : remise à zéro complète du moteur, puis nouvel essai.
            engine.reset()
            schedule(from: AVAudioFramePosition(pausedTime * file.processingFormat.sampleRate))
            guard startEngine() else {
                AudioLog.add("Échec : le moteur ne démarre pas")
                isPlaying = false
                updateNowPlaying()
                return
            }
            node.play()
            didStartPlaying()
            return
        }
        node.play()
        didStartPlaying()
    }

    private func didStartPlaying() {
        if UIApplication.shared.applicationState == .active {
            engine.mainMixerNode.outputVolume = 0
            fade(to: 1, duration: 0.25)
        } else {
            cancelFade()
        }
        isPlaying = true
        currentTime = pausedTime
        recoveryFailures = 0
        startClock()
        updateNowPlaying()
        AudioLog.add("Lecture en cours · moteur=\(engine.isRunning) · nœud=\(node.isPlaying)")
    }

    private func appStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "arrière-plan"
        @unknown default: return "?"
        }
    }

    func pause() {
        pausedTime = position()
        AudioLog.add("Pause · t=\(Int(pausedTime))s")
        currentTime = pausedTime
        isPlaying = false
        stopClock()
        updateNowPlaying()
        saveState()
        if UIApplication.shared.applicationState == .active && engine.isRunning {
            fade(to: 0, duration: 0.2) { [weak self] in
                guard let self = self, !self.isPlaying else { return }
                self.node.pause()
            }
        } else {
            cancelFade()
            node.pause()
        }
    }

    private func cancelFade() {
        fadeToken += 1
        fadeTimer?.invalidate()
        fadeTimer = nil
        engine.mainMixerNode.outputVolume = 1
    }

    private func fade(to target: Float, duration: Double, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeToken += 1
        let token = fadeToken
        let mixer = engine.mainMixerNode
        let start = mixer.outputVolume
        let steps = 10
        fadeStep = 0
        let timer = Timer(timeInterval: duration / Double(steps), repeats: true) { [weak self] timer in
            guard let self = self, self.fadeToken == token else {
                timer.invalidate()
                return
            }
            self.fadeStep += 1
            let step = self.fadeStep
            mixer.outputVolume = start + (target - start) * Float(step) / Float(steps)
            if step >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    // MARK: - Reprise au lancement

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(queue.map { $0.path }, forKey: "audioQueue")
        defaults.set(index, forKey: "audioIndex")
        defaults.set(isPlaying ? position() : pausedTime, forKey: "audioTime")
    }

    /// Retrouve la file et la position de la dernière fois (en pause).
    func restore(from tracks: [Track]) {
        guard queue.isEmpty else { return }
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: "audioQueue") ?? []
        let byPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let restored = paths.compactMap { byPath[$0] }.filter { $0.exists && $0.isAudio }
        guard !restored.isEmpty else { return }
        original = restored
        queue = restored
        index = min(max(0, defaults.integer(forKey: "audioIndex")), restored.count - 1)
        load(play: false, at: defaults.double(forKey: "audioTime"))
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .off {
            seek(to: 0)
            pause()
            return
        } else {
            index = 0
        }
        load(play: true)
    }

    func previous() {
        if position() > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        load(play: true)
    }

    func seek(to seconds: Double) {
        guard let file = file else {
            pausedTime = max(0, seconds)
            currentTime = pausedTime
            return
        }
        let sampleRate = file.processingFormat.sampleRate
        let target = max(0, min(seconds, max(0, duration - 0.25)))
        let wasPlaying = isPlaying
        schedule(from: AVAudioFramePosition(target * sampleRate))
        pausedTime = target
        currentTime = target
        if wasPlaying {
            startEngine()
            node.play()
        }
        updateNowPlaying()
    }

    func stop() {
        generation += 1
        node.stop()
        file = nil
        queue = []
        original = []
        index = 0
        isPlaying = false
        currentTime = 0
        duration = 0
        stopClock()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        saveState()
    }

    /// Un fichier a été supprimé, déplacé ou compressé : on le retire de la file.
    func forget(path: String) {
        guard queue.contains(where: { $0.path == path }) else { return }
        if current?.path == path {
            stop()
            return
        }
        let now = current
        queue.removeAll { $0.path == path }
        original.removeAll { $0.path == path }
        index = queue.firstIndex(where: { $0.id == now?.id }) ?? 0
    }

    // MARK: - Moteur

    private func load(play: Bool, at time: Double = 0) {
        cancelFade()
        AudioLog.add("Chargement · lecture=\(play) · t=\(Int(time))s · n°\(index + 1)")
        guard let track = current else { return }
        guard FileManager.default.fileExists(atPath: track.path) else {
            onMessage?(L("Fichier introuvable (supprimé ou déplacé)."))
            if index + 1 < queue.count {
                index += 1
                load(play: play)
            }
            return
        }
        let opened: AVAudioFile
        do {
            opened = try AVAudioFile(forReading: track.fileURL)
        } catch {
            onMessage?(L("Lecture impossible : « {title} ».", ["title": track.title]))
            if index + 1 < queue.count {
                index += 1
                load(play: play)
            } else {
                isPlaying = false
            }
            return
        }
        generation += 1
        node.stop()
        file = opened
        let format = opened.processingFormat
        if connectedFormat == nil || connectedFormat?.sampleRate != format.sampleRate
            || connectedFormat?.channelCount != format.channelCount {
            let tapWasOn = tapInstalled
            if tapWasOn {
                engine.mainMixerNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            connectChain(format)
            if tapWasOn { updateTap() }
        }
        let fileDuration = Double(opened.length) / format.sampleRate
        duration = fileDuration > 0 ? fileDuration : (MediaLibrary.shared.duration(track) ?? 0)
        let begin = min(max(0, time), max(0, duration - 0.5))
        schedule(from: AVAudioFramePosition(begin * format.sampleRate))
        pausedTime = begin
        currentTime = begin
        if play {
            takeOverFromVideo()
            activateSession()
            startEngine()
            node.play()
            isPlaying = true
            startClock()
        } else {
            isPlaying = false
        }
        remember(track)
        loadArtwork(for: track)
        updateNowPlaying()
        saveState()
    }

    /// Lecteur → vitesse → égaliseur → mixeur, au format du fichier.
    private func connectChain(_ format: AVAudioFormat?) {
        engine.disconnectNodeOutput(node)
        engine.disconnectNodeOutput(pitch)
        engine.disconnectNodeOutput(equalizer)
        engine.connect(node, to: pitch, format: format)
        engine.connect(pitch, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file = file else { return }
        generation += 1
        let token = generation
        node.stop()
        let start = max(0, min(frame, file.length))
        startFrame = start
        let remaining = file.length - start
        guard remaining > 0 else { return }
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil,
                             completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                // Ce rappel arrive aussi quand iOS arrête le son (app en arrière-plan, appel…) :
                // on ne passe au morceau suivant que si la lecture allait vraiment jusqu'au bout.
                guard let self = self, self.generation == token, self.isPlaying, self.engine.isRunning,
                      // Rappel aussi envoyé quand iOS arrête le lecteur : on ne passe au suivant
                      // que si le morceau est vraiment arrivé à la fin (sinon : sauts de morceaux).
                      self.duration > 0, self.position() >= self.duration - 1.0 else { return }
                AudioLog.add("Fin du morceau n°\(self.index + 1)")
                self.finished()
            }
        }
    }

    @discardableResult
    private func startEngine() -> Bool {
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            AudioLog.add("Moteur non démarré : \((error as NSError).code)")
            onMessage?(L("Le son n'a pas pu démarrer. Réessayez."))
            return false
        }
    }

    /// Position réelle de lecture (en secondes).
    private func position() -> Double {
        guard isPlaying else { return pausedTime }
        // Moteur arrêté par iOS : on garde la dernière position lue (et non le début du morceau).
        guard let file = file, engine.isRunning, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return currentTime }
        let seconds = Double(startFrame + playerTime.sampleTime) / file.processingFormat.sampleRate
        return max(0, min(seconds, duration))
    }

    private func finished() {
        if repeatMode == .one {
            schedule(from: 0)
            pausedTime = 0
            currentTime = 0
            node.play()
            updateNowPlaying()
            return
        }
        if index + 1 < queue.count || repeatMode == .all {
            next()
        } else {
            isPlaying = false
            stopClock()
            schedule(from: 0)
            pausedTime = 0
            currentTime = 0
            updateNowPlaying()
            saveState()
        }
    }

    private func startClock() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // iOS a coupé le son sans prévenir : on passe en pause à la bonne position.
            if self.isPlaying && !self.engine.isRunning {
                self.recoverEngine(resume: true)
                return
            }
            self.currentTime = self.position()
            // Fin du morceau détectée par la position (au cas où iOS n'envoie pas le rappel).
            if self.duration > 1, self.currentTime >= self.duration - 0.05, self.node.isPlaying {
                AudioLog.add("Fin du morceau n°\(self.index + 1) (position)")
                self.finished()
                return
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopClock() {
        ticker?.invalidate()
        ticker = nil
    }

    /// « Écoutés récemment » (accueil).
    private func remember(_ track: Track) {
        var list = recent.filter { $0 != track.path }
        list.insert(track.path, at: 0)
        if list.count > 40 { list = Array(list.prefix(40)) }
        recent = list
        UserDefaults.standard.set(list, forKey: "recentlyPlayed")
    }

    @discardableResult
    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true)
            return true
        } catch {
            AudioLog.add("Session audio refusée : \((error as NSError).code)")
            return false
        }
    }

    // MARK: - Égaliseur

    private static func savedGains() -> [Float] {
        let saved = UserDefaults.standard.array(forKey: "eqGains") as? [Float] ?? []
        return saved.count == 10 ? saved : Array(repeating: 0, count: 10)
    }

    private func configureEqualizer() {
        for (offset, band) in equalizer.bands.enumerated() {
            band.frequency = AudioPlayer.bandFrequencies[offset]
            band.bandwidth = 1
            if offset == 0 {
                band.filterType = .lowShelf
            } else if offset == equalizer.bands.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            band.bypass = false
        }
        applyEqualizer()
    }

    private func applyEqualizer() {
        for (offset, band) in equalizer.bands.enumerated() {
            band.gain = eqEnabled ? eqGains[offset] : 0
        }
        // Évite la saturation quand on monte beaucoup les basses.
        let peak = eqEnabled ? (eqGains.max() ?? 0) : 0
        equalizer.globalGain = peak > 3 ? -(peak - 3) * 0.6 : 0
    }

    func setEqualizer(enabled: Bool) {
        eqEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "eqEnabled")
        applyEqualizer()
    }

    func setGain(_ gain: Float, band: Int) {
        guard eqGains.indices.contains(band) else { return }
        eqGains[band] = max(-12, min(12, gain))
        eqPreset = "custom"
        if !eqEnabled { eqEnabled = true }
        saveEqualizer()
    }

    func applyPreset(_ id: String) {
        guard let preset = AudioPlayer.presets.first(where: { $0.id == id }) else { return }
        eqGains = preset.gains
        eqPreset = id
        eqEnabled = true
        saveEqualizer()
    }

    private func saveEqualizer() {
        UserDefaults.standard.set(eqEnabled, forKey: "eqEnabled")
        UserDefaults.standard.set(eqGains, forKey: "eqGains")
        UserDefaults.standard.set(eqPreset, forKey: "eqPreset")
        applyEqualizer()
    }

    // MARK: - Spectre (visualiseur)

    private func updateTap() {
        let wanted = spectrumWanted
        if wanted && !tapInstalled {
            let mixer = engine.mainMixerNode
            let format = mixer.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return }
            mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                let bands = self.analyzer.analyze(buffer)
                guard !bands.isEmpty else { return }
                DispatchQueue.main.async {
                    guard Date().timeIntervalSince(self.lastSpectrum) > 0.03 else { return }
                    self.lastSpectrum = Date()
                    var smoothed = self.spectrum
                    for offset in smoothed.indices where offset < bands.count {
                        let value = bands[offset]
                        smoothed[offset] = value > smoothed[offset] ? value : smoothed[offset] * 0.8 + value * 0.2
                    }
                    self.spectrum = smoothed
                }
            }
            tapInstalled = true
        } else if !wanted && tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
            spectrum = Array(repeating: 0, count: AudioPlayer.bandCount)
        }
    }

    /// Niveau des basses (0…1), pour faire « respirer » les animations.
    var bass: Float {
        let low = spectrum.prefix(5)
        return low.isEmpty ? 0 : low.reduce(0, +) / Float(low.count)
    }

    // MARK: - Minuteur de sommeil

    func setSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEnd = nil
        guard minutes > 0 else { return }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepEnd = end
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            self?.pause()
            self?.sleepEnd = nil
            self?.onMessage?(L("Minuteur de sommeil : lecture mise en pause."))
        }
    }

    // MARK: - Écran verrouillé et Centre de contrôle

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.play() } else { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.pause() } else { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.toggle() } else { self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.next() } else { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.previous() } else { self?.previous() }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            if let video = VideoPlayerModel.active, video.player.currentItem != nil { video.seek(to: event.positionTime) } else { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        if let video = VideoPlayerModel.active, video.player.currentItem != nil { return }
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let library = MediaLibrary.shared
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: library.title(track),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: isPlaying ? position() : pausedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
        if let artist = library.knownArtist(track) {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = library.album(track) {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = artwork, artworkKey == track.id {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: Track) {
        guard artworkKey != track.id else { return }
        artwork = nil
        artworkKey = nil
        guard let link = MediaLibrary.shared.artwork(track), let url = URL(string: link) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self = self, self.current?.id == track.id else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.artworkKey = track.id
                self.updateNowPlaying()
            }
        }.resume()
    }
}

/// Analyse du son (FFT) pour le visualiseur : renvoie des bandes 0…1, espacées comme l'oreille.
final class SpectrumAnalyzer {
    private let size = 1024
    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup?
    private var window: [Float]
    private let bandCount: Int
    private var peak: Float = 0.001
    private let lock = NSLock()

    init(bands: Int) {
        bandCount = bands
        setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = setup { vDSP_destroy_fftsetup(setup) }
    }

    func analyze(_ buffer: AVAudioPCMBuffer) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard let setup = setup, let channels = buffer.floatChannelData, Int(buffer.frameLength) >= size else {
            return []
        }
        let half = size / 2
        var samples = [Float](repeating: 0, count: size)
        vDSP_vmul(channels[0], 1, window, 1, &samples, 1, vDSP_Length(size))
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                guard let realBase = realPointer.baseAddress, let imaginaryBase = imaginaryPointer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                samples.withUnsafeBytes { raw in
                    guard let complex = raw.baseAddress?.assumingMemoryBound(to: DSPComplex.self) else { return }
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        var bands = [Float](repeating: 0, count: bandCount)
        let maxBin = Float(half - 1)
        for band in 0..<bandCount {
            let low = Int(pow(maxBin, Float(band) / Float(bandCount)))
            let high = max(low + 1, Int(pow(maxBin, Float(band + 1) / Float(bandCount))))
            var sum: Float = 0
            for bin in max(1, low)..<min(half, high + 1) {
                sum += magnitudes[bin]
            }
            let count = Float(max(1, min(half, high + 1) - max(1, low)))
            bands[band] = sqrt(sum / count)
        }
        let loudest = bands.max() ?? 0
        peak = max(peak * 0.995, loudest, 0.001)
        return bands.map { min(1, pow($0 / peak, 0.8)) }
    }
}
