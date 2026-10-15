import AVFoundation
import LocalAuthentication
import SwiftUI
import UIKit

final class JobStore: ObservableObject {
    @Published var jobs: [Job] = []
}

struct Toast: Identifiable, Equatable {
    enum Kind {
        case info, ok, warn, error
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

let standardQualities = ["Meilleure", "1080p", "720p", "480p", "360p"]

/// État de l'app : bibliothèque (musique, vidéos, fichiers), lecture,
/// téléchargements, Coffre, messages. Les données passent par le moteur Python.
final class AppModel: ObservableObject {
    // Moteur
    @Published private(set) var engineReady = false
    @Published private(set) var engineError: String?
    @Published private(set) var engineInfo: [String: String] = [:]

    // Bibliothèque
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var favoriteTracks: [Track] = []
    @Published private(set) var vault: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var libraryLoaded = false

    // File
    /// File des téléchargements (à part : elle change souvent pendant un téléchargement).
    let jobStore = JobStore()
    var jobs: [Job] { jobStore.jobs }
    @Published private(set) var compressing: Set<String> = []

    // Écran Télécharger
    @Published var linkText = UserDefaults.standard.string(forKey: "linkText") ?? "" {
        didSet { UserDefaults.standard.set(linkText, forKey: "linkText") }
    }
    @Published var media = UserDefaults.standard.string(forKey: "defaultMedia") ?? "video"
    @Published var quality = UserDefaults.standard.string(forKey: "defaultQuality") ?? "Meilleure"
    @Published private(set) var qualities = standardQualities
    @Published private(set) var analysis: Analysis?
    @Published private(set) var analyzing = false
    @Published private(set) var analysisMessage: String?
    @Published private(set) var analysisIsError = false

    // Recherche en ligne (YouTube)
    @Published private(set) var onlineResults: [WebResult] = []
    @Published private(set) var searchingOnline = false
    @Published private(set) var onlineQuery = ""

    // Lecture vidéo et navigateur
    @Published var videoSession: VideoSession?
    @Published var showBrowser = false
    @Published var showSearch = false
    @Published var showNowPlaying = false

    // Navigation et sécurité
    // Navigation retenue d'une ouverture à l'autre (onglet et écrans ouverts).
    @Published var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "lastTab") ?? "")
        .flatMap { $0 == .browser ? nil : $0 } ?? .home {
        didSet { if tab != .browser { UserDefaults.standard.set(tab.rawValue, forKey: "lastTab") } }
    }
    @Published var libraryPath: [LibraryRoute] = AppModel.loadPath("libraryPath") {
        didSet { AppModel.savePath(libraryPath, "libraryPath") }
    }
    @Published var homePath: [LibraryRoute] = AppModel.loadPath("homePath") {
        didSet { AppModel.savePath(homePath, "homePath") }
    }
    @Published var searchPath: [LibraryRoute] = AppModel.loadPath("searchPath") {
        didSet { AppModel.savePath(searchPath, "searchPath") }
    }
    @Published private(set) var vaultUnlocked = false
    @Published private(set) var appLocked = false
    @Published var toast: Toast?

    private let engine = PythonEngine.shared
    private var timer: Timer?
    private var polling = false
    private var libraryRev = -1
    private var analysisToken = UUID()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var searchToken = UUID()
    private weak var audio: AudioPlayer?
    private var lastRescan = Date.distantPast

    private static func loadPath(_ key: String) -> [LibraryRoute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let path = try? JSONDecoder().decode([LibraryRoute].self, from: data) else { return [] }
        return path.filter { $0 != .vault }
    }

    private static func savePath(_ path: [LibraryRoute], _ key: String) {
        // Le Coffre n'est jamais rouvert tout seul.
        let safe = path.filter { $0 != .vault }
        if let data = try? JSONEncoder().encode(safe) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    init() {
        Lang.apply(UserDefaults.standard.string(forKey: "language") ?? "system")
        if UserDefaults.standard.bool(forKey: "appLock") {
            appLocked = true
        }
        startEngine()
    }

    // MARK: - Moteur

    private func startEngine() {
        // Le moteur parle toujours français : l'app traduit ensuite dans la langue choisie.
        let language = "fr"
        engine.queue.async { [weak self] in
            let result = PythonEngine.shared.start(language: language)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = result["error"] as? String {
                    self.engineError = error
                    return
                }
                var info: [String: String] = [:]
                for key in ["python", "ytdlp"] {
                    if let value = jsonString(result[key]) { info[key] = value }
                }
                info["javascript"] = jsonBool(result["javascript"]) ? "1" : "0"
                self.engineInfo = info
                self.engineReady = true
                self.applyEngineSettings()
                self.refreshLibrary()
                self.startPolling()
                if !self.linkText.isEmpty && self.analysis == nil && !self.analyzing {
                    self.analyzeLinks()
                }
            }
        }
    }

    func attach(_ player: AudioPlayer) {
        audio = player
        player.onMessage = { [weak self] text in
            self?.show(text, .warn)
        }
    }

    /// L'Image dans l'image doit laisser voir le reste de l'app (comme Safari) :
    /// on referme juste l'écran plein écran, la lecture continue dans la mini-fenêtre.
    func attach(_ video: VideoPlayerModel) {
        video.onPictureInPictureStart = { [weak self] in
            self?.videoSession = nil
        }
        video.onPictureInPictureRestore = { [weak video, weak self] in
            guard let self = self, let video = video, video.current != nil, self.videoSession == nil else { return }
            self.videoSession = VideoSession(items: video.items, start: video.index)
        }
    }

    func setEngineLanguage() {
        engine.run("language", ["language": "fr"])
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func poll() {
        guard engineReady, !polling else { return }
        polling = true
        engine.run("poll") { [weak self] result in
            guard let self = self else { return }
            self.polling = false
            guard result["error"] == nil else { return }
            let newJobs = (result["jobs"] as? [[String: Any]] ?? []).map { Job($0) }
            if newJobs != self.jobStore.jobs {
                self.jobStore.jobs = newJobs
            }
            for event in result["events"] as? [[String: Any]] ?? [] {
                self.handle(event)
            }
            let rev = Int(jsonDouble(result["rev"]) ?? 0)
            if rev != self.libraryRev {
                self.refreshLibrary()
            }
            self.updateIdleTimer(active: jsonBool(result["active"]))
        }
    }

    private func handle(_ event: [String: Any]) {
        let kind = jsonString(event["kind"]) ?? ""
        let title = jsonString(event["title"]) ?? ""
        switch kind {
        case "finished":
            show(L("Terminé : {title}", ["title": title]), .ok)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            refreshLibrary()
            let savePhotos = UserDefaults.standard.object(forKey: "saveToPhotos") as? Bool ?? true
            let mediaType = jsonString(event["media_type"]) ?? "video"
            if savePhotos && mediaType != "audio" {
                let path = jsonString(event["filepath"]) ?? ""
                let photos = (event["photos"] as? [Any] ?? []).compactMap { jsonString($0) }
                let ext = (path as NSString).pathExtension.lowercased()
                let video = videoExtensions.contains(ext) ? URL(fileURLWithPath: path) : nil
                PhotoSaver.save(video: video, images: photos.map { URL(fileURLWithPath: $0) }) { _ in }
            }
        case "failed":
            if tab != .download {
                show(L("Échec : {title}", ["title": title]), .error)
            }
        case "network":
            if jsonBool(event["online"]) {
                show(L("Connexion rétablie : reprise des téléchargements."), .ok)
            } else {
                show(L("Pas de connexion internet : les téléchargements reprendront tout seuls."), .warn)
            }
        default:
            break
        }
    }

    func refreshLibrary() {
        guard engineReady else { return }
        engine.run("library") { [weak self] result in
            guard let self = self, result["error"] == nil else { return }
            self.libraryRev = Int(jsonDouble(result["rev"]) ?? 0)
            let entries = (result["entries"] as? [[String: Any]] ?? []).map { Track($0) }
            if entries != self.tracks {
                let gone = Set(self.tracks.map { $0.path }).subtracting(entries.map { $0.path })
                for path in gone where !FileManager.default.fileExists(atPath: path) {
                    self.audio?.forget(path: path)
                }
                self.tracks = entries
            }
            let favs = Set((result["favorites"] as? [Any] ?? []).compactMap { jsonString($0) })
            if favs != self.favorites { self.favorites = favs }
            let favItems = (result["favorite_items"] as? [[String: Any]] ?? []).map { Track($0) }
            if favItems != self.favoriteTracks { self.favoriteTracks = favItems }
            let vaultItems = (result["vault"] as? [[String: Any]] ?? []).map { Track($0) }
            if vaultItems != self.vault { self.vault = vaultItems }
            let lists = (result["playlists"] as? [[String: Any]] ?? []).map { Playlist($0) }
            if lists != self.playlists { self.playlists = lists }
            if !self.libraryLoaded {
                self.audio?.restore(from: self.tracks)
            }
            self.libraryLoaded = true
            MediaLibrary.shared.scan(self.tracks + self.favoriteTracks + self.vault)
        }
    }

    /// Relit le dossier de Faxel (fichiers ajoutés avec 3uTools, iTunes ou l'app Fichiers).
    func rescan(force: Bool = false, completion: (() -> Void)? = nil) {
        guard engineReady else {
            completion?()
            return
        }
        guard force || Date().timeIntervalSince(lastRescan) > 3 else {
            completion?()
            return
        }
        lastRescan = Date()
        engine.run("rescan") { [weak self] result in
            guard let self = self else { return }
            let added = Int(jsonDouble(result["added"]) ?? 0)
            if added > 0 {
                self.show(L("{count} fichier(s) ajouté(s) à la bibliothèque.", ["count": "\(added)"]), .ok)
            }
            self.refreshLibrary()
            completion?()
        }
    }

    // MARK: - Listes de la bibliothèque

    var songs: [Track] { tracks.filter { $0.isAudio && $0.exists } }
    var videos: [Track] { tracks.filter { $0.isVideo && $0.exists } }
    var downloads: [Track] { tracks.filter { $0.isDownloaded } }

    var recentlyAdded: [Track] {
        tracks.filter { $0.exists && !$0.isFolder }.sorted { $0.addedDate > $1.addedDate }
    }

    func track(path: String) -> Track? {
        tracks.first { $0.path == path } ?? favoriteTracks.first { $0.path == path } ?? vault.first { $0.path == path }
    }

    // MARK: - Import de fichiers (Fichiers, « Ouvrir avec Faxel »)

    static var importFolder: URL {
        PythonEngine.documentsURL.appendingPathComponent(Lang.code == "en" ? "Imported" : "Importés", isDirectory: true)
    }

    /// Importe des fichiers (ou des dossiers entiers, avec leurs sous-dossiers) choisis
    /// dans l'app Fichiers : chaque son/vidéo reconnu est copié dans Faxel.
    func importFiles(_ urls: [URL], completion: (([String]) -> Void)? = nil) {
        let folder = AppModel.importFolder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var copied = 0
            var refused = 0
            var paths: [String] = []
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let result = Self.copyFolder(url, into: folder)
                    copied += result.paths.count
                    refused += result.refused
                    paths += result.paths
                    continue
                }
                let ext = url.pathExtension.lowercased()
                guard audioExtensions.contains(ext) || videoExtensions.contains(ext) || subtitleExtensions.contains(ext) else {
                    refused += 1
                    continue
                }
                if url.path.hasPrefix(PythonEngine.documentsURL.path) {
                    copied += 1
                    paths.append(url.path)
                    continue
                }
                let target = AppModel.uniqueURL(folder.appendingPathComponent(url.lastPathComponent))
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    copied += 1
                    paths.append(target.path)
                } catch {
                    refused += 1
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if copied > 0 {
                    self.show(L("{count} fichier(s) importé(s).", ["count": "\(copied)"]), .ok)
                }
                if refused > 0 {
                    self.show(L("{count} fichier(s) non pris en charge (formats lus : MP3, M4A, AAC, WAV, FLAC, AIFF, MP4, MOV, M4V).",
                                ["count": "\(refused)"]), .warn)
                }
                completion?(paths)
                self.rescan(force: true)
            }
        }
    }

    /// Copie récursivement un dossier choisi dans Fichiers (et ses sous-dossiers) :
    /// seuls les sons, vidéos et sous-titres reconnus sont retenus.
    private static func copyFolder(_ source: URL, into destination: URL) -> (paths: [String], refused: Int) {
        var paths: [String] = []
        var refused = 0
        let target = uniqueURL(destination.appendingPathComponent(source.lastPathComponent))
        guard let items = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else {
            return ([], 0)
        }
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            let ext = item.pathExtension.lowercased()
            guard audioExtensions.contains(ext) || videoExtensions.contains(ext) || subtitleExtensions.contains(ext) else {
                refused += 1
                continue
            }
            let relative = item.path.hasPrefix(source.path) ? String(item.path.dropFirst(source.path.count)) : item.lastPathComponent
            let itemTarget = target.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(at: itemTarget.deletingLastPathComponent(),
                                                      withIntermediateDirectories: true)
            do {
                try FileManager.default.copyItem(at: item, to: itemTarget)
                paths.append(itemTarget.path)
            } catch {
                refused += 1
            }
        }
        return (paths, refused)
    }

    static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        for number in 2...9999 {
            let name = ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
    }

    /// Lien ou fichier reçu d'une autre app.
    func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            importFiles([url])
        } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            openDownload(url.absoluteString, analyze: true)
        } else if url.scheme?.lowercased() == "faxel", let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value {
            openDownload(link, analyze: true)
        }
    }

    private func updateIdleTimer(active: Bool) {
        let keepAwake = UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true
        ScreenAwake.set("downloads", keepAwake && active)
    }

    // MARK: - Messages

    func show(_ text: String, _ kind: Toast.Kind = .info) {
        let toast = Toast(text: text, kind: kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            self.toast = toast
        }
        let delay: Double = kind == .error ? 5 : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.toast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    // MARK: - Écran Télécharger

    /// Liens http(s) du texte, sans doublons.
    func links(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: [String] = []
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            let link = url.absoluteString
            if !found.contains(link) { found.append(link) }
        }
        return found
    }

    var currentLinks: [String] { links(in: linkText) }

    func pasteLinks() {
        let text = UIPasteboard.general.string ?? ""
        if text.isEmpty {
            show(L("Le presse-papiers est vide."), .warn)
            return
        }
        let found = links(in: text)
        if found.isEmpty {
            show(L("Le presse-papiers ne contient pas de lien."), .warn)
            return
        }
        var all = currentLinks
        for link in found where !all.contains(link) { all.append(link) }
        linkText = all.joined(separator: "\n")
        resetAnalysis()
        if all.count == 1 { analyzeLinks() }
    }

    /// Téléchargement en un geste : colle le lien et lance aussitôt avec les réglages actuels.
    func pasteAndDownload() {
        let text = UIPasteboard.general.string ?? ""
        if text.isEmpty {
            show(L("Le presse-papiers est vide."), .warn)
            return
        }
        let found = links(in: text)
        if found.isEmpty {
            show(L("Le presse-papiers ne contient pas de lien."), .warn)
            return
        }
        var all = currentLinks
        for link in found where !all.contains(link) { all.append(link) }
        linkText = all.joined(separator: "\n")
        resetAnalysis()
        if all.count == 1 {
            analyzeLinks(autoDownload: true)
        } else {
            startDownload()
        }
    }

    func clearLinks() {
        linkText = ""
        resetAnalysis()
    }

    func resetAnalysis() {
        analysisToken = UUID()
        analysis = nil
        analyzing = false
        analysisMessage = nil
        analysisIsError = false
        qualities = standardQualities
        if !qualities.contains(quality) { quality = "Meilleure" }
    }

    /// Ouvre l'écran Télécharger avec un lien (depuis le Navigateur ou une autre app).
    func openDownload(_ link: String, analyze: Bool) {
        linkText = link
        resetAnalysis()
        showBrowser = false
        tab = .download
        if analyze { analyzeLinks() }
    }

    func analyzeLinks(autoDownload: Bool = false) {
        let found = currentLinks
        guard !found.isEmpty else {
            show(L("Collez d'abord un lien."), .warn)
            return
        }
        if found.count > 1 {
            analysis = nil
            analysisIsError = false
            analysisMessage = L("{count} liens : ils seront téléchargés avec les options choisies.",
                                ["count": "\(found.count)"])
            if autoDownload { startDownload() }
            return
        }
        guard engineReady else {
            analysisMessage = L("Le moteur démarre, réessayez dans un instant.")
            return
        }
        let token = UUID()
        analysisToken = token
        analyzing = true
        analysis = nil
        analysisIsError = false
        analysisMessage = L("Analyse en cours…")
        engine.run("analyze", ["url": found[0]], slow: true) { [weak self] result in
            guard let self = self, self.analysisToken == token else { return }
            self.analyzing = false
            if let info = result["info"] as? [String: Any] {
                self.apply(Analysis(info))
            } else {
                let message = jsonString(result["error_message"]) ?? jsonString(result["error"]) ?? ""
                self.analysisIsError = true
                self.analysisMessage = message.isEmpty ? L("Analyse impossible. Vous pouvez quand même lancer le téléchargement.") : L(message)
            }
            if autoDownload { self.startDownload() }
        }
    }

    private func apply(_ info: Analysis) {
        analysis = info
        analysisMessage = nil
        analysisIsError = false
        switch info.kind {
        case "photo":
            qualities = ["Meilleure"]
            quality = "Meilleure"
            analysisMessage = L("Vidéo : les photos (et la musique). Audio : la musique seule.")
        case "playlist":
            qualities = standardQualities
        default:
            qualities = info.qualities.isEmpty ? standardQualities : info.qualities
            if !qualities.contains(quality) {
                let wanted = UserDefaults.standard.string(forKey: "defaultQuality") ?? "Meilleure"
                quality = qualities.contains(wanted) ? wanted : (qualities.first ?? "Meilleure")
            }
            if !info.videoOK && info.audioOK {
                media = "audio"
                analysisMessage = L("Seul l'audio est disponible dans un format compatible.")
            } else if !info.videoOK && !info.audioOK {
                analysisIsError = true
                analysisMessage = L("Aucun format compatible n'a été trouvé pour ce contenu.")
            }
        }
    }

    var startTitle: String {
        let count = currentLinks.count
        if count > 1 { return L("Télécharger les {count} liens", ["count": "\(count)"]) }
        if analysis?.kind == "playlist" { return L("Télécharger la 1re vidéo") }
        return L("Télécharger")
    }

    func startDownload() {
        let found = currentLinks
        guard !found.isEmpty else {
            show(L("Collez d'abord un lien."), .warn)
            return
        }
        var items: [[String: Any]] = []
        if found.count == 1, let info = analysis {
            if info.kind == "playlist", let first = info.entries.first {
                items = [["url": first.url, "title": first.title]]
            } else {
                items = [["url": info.url.isEmpty ? found[0] : info.url, "title": info.title]]
            }
        } else {
            items = found.map { ["url": $0] }
        }
        enqueue(items)
    }

    func startAll() {
        guard let info = analysis, !info.entries.isEmpty else { return }
        enqueue(info.entries.map { ["url": $0.url, "title": $0.title] })
    }

    private func enqueue(_ items: [[String: Any]]) {
        guard engineReady else {
            show(L("Le moteur démarre, réessayez dans un instant."), .warn)
            return
        }
        let args: [String: Any] = ["items": items, "media_type": media,
                                   "quality": media == "audio" ? "Meilleure" : quality]
        engine.run("import", args) { [weak self] result in
            guard let self = self else { return }
            let count = Int(jsonDouble(result["count"]) ?? 0)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.show(L("{count} téléchargement(s) ajouté(s) à la file.", ["count": "\(count)"]), .ok)
            self.linkText = ""
            self.resetAnalysis()
            self.tab = .download
            self.poll()
        }
    }

    /// Analyse d'un lien pour la feuille « Télécharger ».
    func analyze(_ url: String, playlist: Bool = false, completion: @escaping (Analysis?, String?) -> Void) {
        guard engineReady else {
            completion(nil, L("Le moteur démarre, réessayez dans un instant."))
            return
        }
        engine.run("analyze", ["url": url, "playlist": playlist], slow: true) { result in
            if let info = result["info"] as? [String: Any] {
                completion(Analysis(info), nil)
            } else {
                let message = jsonString(result["error_message"]) ?? jsonString(result["error"]) ?? ""
                completion(nil, message.isEmpty ? L("Analyse impossible. Vous pouvez quand même lancer le téléchargement.")
                                                : L(message))
            }
        }
    }

    /// Ajout direct à la file (sans changer d'onglet).
    /// Toute la playlist (ou le Mix) de la vidéo regardée.
    func downloadPlaylist(_ url: String, media: String, quality: String, completion: ((Bool) -> Void)? = nil) {
        show(L("Lecture de la playlist…"), .info)
        analyze(url, playlist: true) { [weak self] info, error in
            guard let self = self else { return }
            guard let info = info, !info.entries.isEmpty else {
                self.show(error ?? L("Playlist vide ou introuvable."), .warn)
                completion?(false)
                return
            }
            self.quickDownload(info.entries.map { ["url": $0.url, "title": $0.title] }, media: media,
                               quality: media == "audio" ? "Meilleure" : quality)
            completion?(true)
        }
    }

    func quickDownload(_ items: [[String: Any]], media: String, quality: String) {
        guard engineReady else {
            show(L("Le moteur démarre, réessayez dans un instant."), .warn)
            return
        }
        engine.run("import", ["items": items, "media_type": media, "quality": quality]) { [weak self] result in
            guard let self = self else { return }
            let count = Int(jsonDouble(result["count"]) ?? 0)
            self.show(L("{count} téléchargement(s) ajouté(s) à la file.", ["count": "\(count)"]), .ok)
            self.poll()
        }
    }

    func jobAction(_ action: String, _ job: Job? = nil, force: Bool = false) {
        var args: [String: Any] = ["action": action, "force": force]
        if let job = job { args["id"] = job.id }
        engine.run("job", args) { [weak self] _ in self?.poll() }
    }

    // MARK: - Recherche en ligne

    func searchOnline(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard engineReady else {
            show(L("Le moteur démarre, réessayez dans un instant."), .warn)
            return
        }
        let token = UUID()
        searchToken = token
        onlineQuery = query
        searchingOnline = true
        onlineResults = []
        engine.run("search", ["query": query, "limit": 25], slow: true) { [weak self] result in
            guard let self = self, self.searchToken == token else { return }
            self.searchingOnline = false
            if let error = jsonString(result["error"]) {
                self.show(L("Recherche impossible : {error}", ["error": error]), .error)
                return
            }
            self.onlineResults = (result["results"] as? [[String: Any]] ?? []).map { WebResult($0) }
            if self.onlineResults.isEmpty {
                self.show(L("Aucun résultat"), .info)
            }
        }
    }

    func clearOnlineSearch() {
        searchToken = UUID()
        searchingOnline = false
        onlineResults = []
        onlineQuery = ""
    }

    func download(_ result: WebResult, media: String) {
        guard engineReady else {
            show(L("Le moteur démarre, réessayez dans un instant."), .warn)
            return
        }
        let args: [String: Any] = ["items": [["url": result.url, "title": result.title]], "media_type": media,
                                   "quality": media == "audio" ? "Meilleure" : quality]
        engine.run("import", args) { [weak self] _ in
            guard let self = self else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.show(L("Ajouté aux téléchargements : {title}", ["title": result.title]), .ok)
            self.poll()
        }
    }

    // MARK: - Lecture

    /// Sons → lecteur audio ; vidéos → lecteur vidéo plein écran.
    func play(_ list: [Track], start: Int, shuffled: Bool = false) {
        guard list.indices.contains(start) else { return }
        let first = list[start]
        guard first.exists, FileManager.default.fileExists(atPath: first.path) else {
            show(L("Fichier introuvable (supprimé ou déplacé)."), .warn)
            return
        }
        if first.isAudio {
            let songs = list.filter { $0.isAudio && $0.exists }
            let index = songs.firstIndex(where: { $0.id == first.id }) ?? 0
            audio?.play(songs, start: index, shuffled: shuffled)
            if UserDefaults.standard.object(forKey: "openPlayer") as? Bool ?? false {
                afterClosingSearch { self.showNowPlaying = true }
            }
        } else if first.isVideo {
            var clips = list.filter { $0.isVideo && $0.exists }
            if shuffled {
                clips = [first] + clips.filter { $0.id != first.id }.shuffled()
            }
            let index = clips.firstIndex(where: { $0.id == first.id }) ?? 0
            audio?.pause()
            let session = VideoSession(items: clips, start: index)
            afterClosingSearch { self.videoSession = session }
        }
    }

    /// La Recherche s'ouvre en feuille : on la referme avant d'ouvrir un lecteur par-dessus.
    private func afterClosingSearch(_ action: @escaping () -> Void) {
        guard showSearch else {
            action()
            return
        }
        showSearch = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    func shuffle(_ list: [Track]) {
        let playable = list.filter { $0.exists && !$0.isFolder }
        guard let pick = playable.randomElement() else {
            show(L("Rien à lire pour l'instant."), .info)
            return
        }
        play(playable, start: playable.firstIndex(of: pick) ?? 0, shuffled: true)
    }

    func playFile(_ url: URL) {
        let track = self.track(path: url.path) ?? Track(["filepath": url.path, "title": url.deletingPathExtension().lastPathComponent])
        play([track], start: 0)
    }

    func playNext(_ track: Track) {
        guard track.isAudio else { return }
        audio?.playNext(track)
        show(L("Lu ensuite : {title}", ["title": MediaLibrary.shared.title(track)]), .ok)
    }

    func addToQueue(_ track: Track) {
        guard track.isAudio else { return }
        audio?.addToQueue(track)
        show(L("Ajouté à la file de lecture."), .ok)
    }

    // MARK: - Bibliothèque

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains(track.path)
    }

    private func checkExists(_ track: Track) -> Bool {
        if FileManager.default.fileExists(atPath: track.path) { return true }
        show(L("Fichier introuvable (supprimé ou déplacé)."), .warn)
        return false
    }

    func toggleFavorite(_ track: Track) {
        guard checkExists(track) else { return }
        engine.run("toggle_favorite", ["entry": track.raw]) { [weak self] result in
            guard let self = self else { return }
            if jsonBool(result["favorite"]) {
                self.show(L("Ajouté aux favoris."), .ok)
            } else if result["error"] == nil {
                self.show(L("Retiré des favoris."), .info)
            }
            UISelectionFeedbackGenerator().selectionChanged()
            self.refreshLibrary()
        }
    }

    func add(_ track: Track, to playlist: Playlist) {
        guard checkExists(track) else { return }
        engine.run("playlist_add", ["uid": playlist.id, "entry": track.raw]) { [weak self] result in
            guard let self = self else { return }
            if jsonBool(result["added"]) {
                self.show(L("Ajouté à « {name} ».", ["name": playlist.name]), .ok)
            } else {
                self.show(L("Déjà dans « {name} ».", ["name": playlist.name]), .info)
            }
            self.refreshLibrary()
        }
    }

    func createPlaylist(_ name: String, adding track: Track? = nil, completion: ((String) -> Void)? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = clean.isEmpty ? L("Ma playlist") : clean
        engine.run("playlist_create", ["name": finalName]) { [weak self] result in
            guard let self = self, let uid = jsonString(result["uid"]) else { return }
            if let track = track {
                self.engine.run("playlist_add", ["uid": uid, "entry": track.raw]) { _ in
                    self.show(L("Ajouté à « {name} ».", ["name": finalName]), .ok)
                    self.refreshLibrary()
                }
            } else {
                self.show(L("« {name} » créée.", ["name": finalName]), .ok)
                self.refreshLibrary()
            }
            completion?(uid)
        }
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        engine.run("playlist_rename", ["uid": playlist.id, "name": name]) { [weak self] _ in
            self?.refreshLibrary()
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        engine.run("playlist_delete", ["uid": playlist.id]) { [weak self] _ in
            self?.show(L("« {name} » supprimée.", ["name": playlist.name]), .info)
            self?.refreshLibrary()
        }
    }

    func remove(_ track: Track, from playlist: Playlist) {
        engine.run("playlist_remove", ["uid": playlist.id, "filepath": track.path]) { [weak self] _ in
            self?.refreshLibrary()
        }
    }

    func delete(_ track: Track, deleteFile: Bool) {
        if deleteFile { audio?.forget(path: track.path) }
        engine.run("delete", ["entry": track.raw, "delete_file": deleteFile]) { [weak self] result in
            if jsonBool(result["ok"]) {
                self?.show(L("Supprimé."), .info)
            } else {
                self?.show(L("Le fichier n'a pas pu être supprimé."), .error)
            }
            self?.refreshLibrary()
        }
    }

    func clearHistory() {
        engine.run("clear_history") { [weak self] _ in
            self?.show(L("Historique effacé."), .info)
            self?.rescan(force: true)
        }
    }

    func playlist(_ id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    func saveToPhotos(_ track: Track) {
        guard checkExists(track) else { return }
        let video = track.isFolder || track.isAudio ? nil : track.fileURL
        PhotoSaver.save(video: video, images: track.photoURLs) { [weak self] ok in
            if ok {
                self?.show(L("Ajouté à l'app Photos."), .ok)
            } else {
                self?.show(L("Impossible d'ajouter à Photos : autorisez Faxel dans Réglages › Confidentialité › Photos."),
                           .warn)
            }
        }
    }

    // MARK: - Coffre

    func authenticate(_ reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true)  // aucun code ni Face ID sur l'iPhone : rien à protéger
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    func openVault() {
        unlockVault { [weak self] in
            guard let self = self else { return }
            self.tab = .library
            self.libraryPath = [.vault]
        }
    }

    func unlockVault(then action: @escaping () -> Void) {
        if vaultUnlocked {
            action()
            return
        }
        authenticate(L("Ouvrir le Coffre de Faxel")) { [weak self] ok in
            guard let self = self else { return }
            if ok {
                self.vaultUnlocked = true
                action()
            } else {
                self.show(L("Coffre verrouillé : identification refusée."), .warn)
            }
        }
    }

    func lockVault() {
        vaultUnlocked = false
    }

    func moveToVault(_ track: Track) {
        guard checkExists(track) else { return }
        audio?.forget(path: track.path)
        engine.run("vault_add", ["entry": track.raw]) { [weak self] result in
            guard let self = self else { return }
            if let error = jsonString(result["error"]) {
                self.show(error == "already" ? L("Déjà dans le Coffre.") : L("Impossible de ranger ce fichier dans le Coffre."),
                          .warn)
            } else {
                self.show(L("Rangé dans le Coffre."), .ok)
            }
            self.refreshLibrary()
        }
    }

    func removeFromVault(_ track: Track) {
        engine.run("vault_remove", ["item": track.raw]) { [weak self] result in
            guard let self = self else { return }
            if result["error"] != nil {
                self.show(L("Impossible de sortir ce fichier du Coffre."), .error)
            } else {
                self.show(L("Sorti du Coffre : de retour dans la bibliothèque."), .info)
            }
            self.refreshLibrary()
        }
    }

    // MARK: - Verrouillage de l'app

    func unlockApp() {
        authenticate(L("Déverrouiller Faxel")) { [weak self] ok in
            if ok {
                withAnimation { self?.appLocked = false }
            }
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            audio?.saveState()
            lockVault()
            if UserDefaults.standard.bool(forKey: "appLock") {
                appLocked = true
            }
            beginBackgroundWork()
        case .active:
            endBackgroundWork()
            if appLocked {
                unlockApp()
            }
            poll()
            rescan()
        default:
            break
        }
    }

    /// Laisse quelques minutes aux téléchargements quand l'app passe en arrière-plan.
    private func beginBackgroundWork() {
        guard backgroundTask == .invalid, jobs.contains(where: { $0.active }) else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Faxel downloads") { [weak self] in
            self?.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Compression

    func compress(_ track: Track) {
        guard checkExists(track) else { return }
        if track.isFolder {
            show(L("Rien à compresser dans un dossier de photos."), .info)
            return
        }
        guard !compressing.contains(track.path) else {
            show(L("Compression déjà en cours pour ce fichier."), .info)
            return
        }
        audio?.forget(path: track.path)
        let source = track.fileURL
        let isVideo = !track.isAudio
        let target = source.deletingPathExtension().appendingPathExtension(isVideo ? "compression.mp4" : "compression.m4a")
        try? FileManager.default.removeItem(at: target)
        let before = fileSize(track.path)
        compressing.insert(track.path)
        show(L("Compression de « {title} »…", ["title": track.title]), .info)
        let finish: (Bool) -> Void = { [weak self] ok in
            guard let self = self else { return }
            self.compressing.remove(track.path)
            let after = fileSize(target.path)
            guard ok, after > 0 else {
                try? FileManager.default.removeItem(at: target)
                self.show(L("Compression impossible pour ce fichier."), .error)
                return
            }
            guard after < before * 0.95 else {
                try? FileManager.default.removeItem(at: target)
                self.show(L("Ce fichier est déjà léger : rien à gagner."), .info)
                return
            }
            do {
                _ = try FileManager.default.replaceItemAt(source, withItemAt: target)
            } catch {
                try? FileManager.default.removeItem(at: target)
                self.show(L("Compression impossible (stockage)."), .error)
                return
            }
            self.engine.run("filesize", ["filepath": track.path, "size": after]) { _ in
                self.refreshLibrary()
            }
            self.show(L("Compressé : {size} (−{saved}).", ["size": Fmt.size(after), "saved": Fmt.size(before - after)]),
                      .ok)
        }
        if isVideo {
            MediaCompressor.compressVideo(source: source, target: target, completion: finish)
        } else {
            MediaCompressor.compressAudio(source: source, target: target, bitrate: 96_000, completion: finish)
        }
    }

    // MARK: - Réglages du moteur, connexions, sauvegarde

    func applyEngineSettings() {
        let defaults = UserDefaults.standard
        let values: [String: Any] = [
            "max_parallel": defaults.object(forKey: "maxParallel") as? Int ?? 2,
            "skip_duplicates": defaults.object(forKey: "skipDuplicates") as? Bool ?? true,
            "clean_titles": defaults.object(forKey: "cleanTitles") as? Bool ?? true,
            "auto_retry": defaults.object(forKey: "autoRetry") as? Bool ?? true,
            "use_browser_cookies": defaults.object(forKey: "useCookies") as? Bool ?? true,
            "allow_av1": DeviceCodecs.av1Supported && (defaults.object(forKey: "allowAV1") as? Bool ?? true),
        ]
        engine.run("settings", ["values": values])
    }

    func forgetCookies() {
        engine.run("forget_cookies") { [weak self] _ in
            self?.show(L("Connexions oubliées par Faxel (celles du navigateur restent actives)."), .ok)
        }
    }

    func openInFiles() {
        let path = PythonEngine.documentsURL.path
        if let url = URL(string: "shareddocuments://" + path), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            show(L("Vos fichiers sont dans l'app Fichiers › Sur mon iPhone › Faxel."), .info)
        }
    }

    func backup() {
        engine.run("backup") { [weak self] result in
            if jsonBool(result["ok"]) {
                self?.show(L("Sauvegarde enregistrée dans l'app Fichiers › Faxel."), .ok)
            } else {
                self?.show(L("Sauvegarde impossible (stockage indisponible)."), .error)
            }
        }
    }

    func restore() {
        engine.run("restore") { [weak self] result in
            guard let self = self else { return }
            if jsonBool(result["ok"]) {
                self.lockVault()
                self.show(L("Sauvegarde restaurée."), .ok)
                self.refreshLibrary()
            } else {
                self.show(L("Aucune sauvegarde trouvée dans l'app Fichiers › Faxel."), .warn)
            }
        }
    }

    func storageText() -> String {
        var used: Double = 0
        let root = PythonEngine.documentsURL
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                used += Double(size)
            }
        }
        var text = L("Fichiers de Faxel : {used}", ["used": Fmt.size(used).isEmpty ? "0" : Fmt.size(used)])
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            text += " · " + L("Libre : {free}", ["free": Fmt.size(Double(free))])
        }
        return text
    }
}

func fileSize(_ path: String) -> Double {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber else { return 0 }
    return size.doubleValue
}
