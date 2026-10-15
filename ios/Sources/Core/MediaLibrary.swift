import AVFoundation
import SwiftUI
import UIKit

/// Informations lues dans le fichier lui-même (balises ID3 / iTunes) :
/// titre, artiste, album, pochette, durée ; image d'aperçu pour les vidéos.
struct MediaMeta: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var trackNumber: Int?
    var hasArtwork = false
    var width: Double?
    var height: Double?
    var modified: Double = 0

    var isLandscape: Bool {
        guard let width = width, let height = height else { return false }
        return width > height
    }
}

/// Un artiste ou un album de la bibliothèque musicale.
struct MusicGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let tracks: [Track]
    let artwork: String?
}

/// Lit les balises des fichiers en arrière-plan et garde le résultat en cache.
final class MediaLibrary: ObservableObject {
    static let shared = MediaLibrary()

    @Published private(set) var metas: [String: MediaMeta] = [:]
    /// Pochettes choisies par l'utilisateur (clé du fichier → nom de l'image).
    @Published private(set) var customCovers: [String: String] = MediaLibrary.loadCustomCovers()

    private let queue = DispatchQueue(label: "faxel.meta", qos: .utility)
    /// Date de modification déjà lue pour chaque fichier (utilisée seulement sur `queue`).
    private var scannedDates: [String: Double] = [:]
    private var saveScheduled = false

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Faxel")
    }

    private static var cacheFile: URL { folder.appendingPathComponent("meta.json") }

    static var artFolder: URL { folder.appendingPathComponent("art", isDirectory: true) }

    private init() {
        try? FileManager.default.createDirectory(at: MediaLibrary.artFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: MediaLibrary.cacheFile),
           let saved = try? JSONDecoder().decode([String: MediaMeta].self, from: data) {
            metas = saved
        }
        scannedDates = metas.mapValues { $0.modified }
    }

    // MARK: - Lecture des balises

    /// Demande la lecture des balises des fichiers nouveaux ou modifiés.
    /// Tout se fait en arrière-plan : la navigation reste fluide même avec des milliers de fichiers.
    func scan(_ tracks: [Track]) {
        let candidates = tracks.filter { $0.exists && !$0.isFolder }.map { ($0.path, $0.isAudio) }
        guard !candidates.isEmpty else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            var todo: [(String, Bool)] = []
            for (path, audio) in candidates {
                let modified = MediaLibrary.modificationDate(path)
                if self.scannedDates[path] == modified { continue }
                self.scannedDates[path] = modified
                todo.append((path, audio))
            }
            guard !todo.isEmpty else { return }
            var batch: [String: MediaMeta] = [:]
            for (index, item) in todo.enumerated() {
                autoreleasepool {
                    batch[item.0] = MediaLibrary.read(path: item.0, audio: item.1)
                }
                if batch.count >= 40 || index == todo.count - 1 {
                    let ready = batch
                    batch = [:]
                    DispatchQueue.main.async {
                        self.merge(ready)
                    }
                }
            }
        }
    }

    /// Une seule mise à jour de l'écran par lot (et non une par fichier).
    private func merge(_ values: [String: MediaMeta]) {
        var updated = metas
        for (path, meta) in values {
            updated[path] = meta
        }
        metas = updated
        scheduleSave()
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.saveScheduled = false
            let snapshot = self.metas
            self.queue.async {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? data.write(to: MediaLibrary.cacheFile, options: .atomic)
                }
            }
        }
    }

    static func modificationDate(_ path: String) -> Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    static func artKey(_ path: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func artURL(_ path: String) -> URL {
        artFolder.appendingPathComponent(artKey(path) + ".jpg")
    }

    private static func read(path: String, audio: Bool) -> MediaMeta {
        var meta = MediaMeta()
        meta.modified = modificationDate(path)
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let seconds = asset.duration.seconds
        if seconds.isFinite && seconds > 0 { meta.duration = seconds }
        var artwork: Data?
        for item in asset.commonMetadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                meta.title = clean(item.stringValue)
            case .commonKeyArtist:
                meta.artist = clean(item.stringValue)
            case .commonKeyAlbumName:
                meta.album = clean(item.stringValue)
            case .commonKeyArtwork:
                if artwork == nil { artwork = item.dataValue }
            default:
                break
            }
        }
        if meta.artist == nil {
            for format in asset.availableMetadataFormats {
                for item in asset.metadata(forFormat: format) {
                    let identifier = item.identifier?.rawValue ?? ""
                    if identifier.hasSuffix("TPE2") || identifier.hasSuffix("aART") {
                        meta.artist = clean(item.stringValue)
                    }
                }
            }
        }
        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                let identifier = item.identifier?.rawValue ?? ""
                if identifier.hasSuffix("TRCK") || identifier.hasSuffix("trkn") {
                    if let text = item.stringValue, let number = Int(text.split(separator: "/").first ?? "") {
                        meta.trackNumber = number
                    } else if let number = item.numberValue {
                        meta.trackNumber = number.intValue
                    } else if let data = item.dataValue, data.count >= 4 {
                        meta.trackNumber = Int(data[3])
                    }
                }
            }
        }
        let target = artURL(path)
        if audio {
            if let data = artwork, let image = UIImage(data: data) {
                meta.hasArtwork = save(image, to: target)
            }
        } else {
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                meta.width = Double(abs(size.width))
                meta.height = Double(abs(size.height))
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let moment = CMTime(seconds: min(2, (meta.duration ?? 4) / 3), preferredTimescale: 600)
            if let image = try? generator.copyCGImage(at: moment, actualTime: nil) {
                meta.hasArtwork = save(UIImage(cgImage: image), to: target)
            }
        }
        return meta
    }

    private static func clean(_ text: String?) -> String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func save(_ image: UIImage, to url: URL) -> Bool {
        let largest = max(image.size.width, image.size.height)
        var output = image
        if largest > 700 {
            let scale = 700 / largest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = output.jpegData(compressionQuality: 0.82) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: - Ce que l'interface affiche

    func meta(_ track: Track) -> MediaMeta? {
        metas[track.path]
    }

    func title(_ track: Track) -> String {
        if track.isAudio, let title = metas[track.path]?.title { return title }
        let raw = track.title.isEmpty ? track.fileURL.deletingPathExtension().lastPathComponent : track.title
        return MediaLibrary.readableTitle(raw, track: track)
    }

    /// « Facebook 2026-10-10 02h39 » n'est pas un vrai titre (publication sans légende) :
    /// on affiche « Vidéo Facebook · 10/10/2026 » à la place.
    private static let siteDatePattern = try? NSRegularExpression(
        pattern: "^\\s*(Facebook|Instagram|TikTok|YouTube|X)\\s*[-–:]?\\s*(\\d{4})-(\\d{2})-(\\d{2})([ T]\\d{1,2}[:h]\\d{2}(:\\d{2})?)?\\s*$",
        options: [.caseInsensitive])

    static func readableTitle(_ text: String, track: Track) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let regex = siteDatePattern, let match = regex.firstMatch(in: text, range: range),
              let site = Range(match.range(at: 1), in: text), let year = Range(match.range(at: 2), in: text),
              let month = Range(match.range(at: 3), in: text), let day = Range(match.range(at: 4), in: text) else {
            return text
        }
        let uploader = track.uploader.trimmingCharacters(in: .whitespaces)
        if !uploader.isEmpty && uploader.lowercased() != text[site].lowercased() {
            return uploader
        }
        return L("Vidéo {site} · {date}", ["site": String(text[site]),
                                           "date": "\(text[day])/\(text[month])/\(text[year])"])
    }

    /// Artiste réel (balises, ou chaîne d'origine du téléchargement), ou nil.
    func knownArtist(_ track: Track) -> String? {
        if let artist = metas[track.path]?.artist { return artist }
        let uploader = track.uploader.trimmingCharacters(in: .whitespaces)
        return uploader.isEmpty ? nil : uploader
    }

    func artist(_ track: Track) -> String {
        knownArtist(track) ?? L("Artiste inconnu")
    }

    func album(_ track: Track) -> String? {
        metas[track.path]?.album
    }

    func duration(_ track: Track) -> Double? {
        track.duration ?? metas[track.path]?.duration
    }

    // MARK: - Pochette personnalisée

    static var coversFolder: URL {
        PythonEngine.dataURL.appendingPathComponent("covers", isDirectory: true)
    }

    private static func loadCustomCovers() -> [String: String] {
        try? FileManager.default.createDirectory(at: coversFolder, withIntermediateDirectories: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: coversFolder.path)) ?? []
        var map: [String: String] = [:]
        for name in names where name.hasSuffix(".jpg") {
            if let key = name.split(separator: "_").first { map[String(key)] = name }
        }
        return map
    }

    func hasCustomCover(_ track: Track) -> Bool {
        customCovers[MediaLibrary.artKey(track.path)] != nil
    }

    /// Remplace la pochette d'un morceau ou d'une vidéo par une photo.
    func setCustomCover(_ image: UIImage, for track: Track) {
        let key = MediaLibrary.artKey(track.path)
        let folder = MediaLibrary.coversFolder
        if let old = customCovers[key] {
            let oldURL = folder.appendingPathComponent(old)
            ImageCache.shared.forget(oldURL)
            try? FileManager.default.removeItem(at: oldURL)
        }
        let name = key + "_" + String(Int(Date().timeIntervalSince1970 * 1000)) + ".jpg"
        let target = folder.appendingPathComponent(name)
        let largest = max(image.size.width, image.size.height)
        var output = image
        if largest > 1200 {
            let scale = 1200 / largest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = output.jpegData(compressionQuality: 0.88) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? data.write(to: target, options: .atomic)) != nil {
            customCovers[key] = name
        }
    }

    func removeCustomCover(for track: Track) {
        let key = MediaLibrary.artKey(track.path)
        guard let name = customCovers[key] else { return }
        let url = MediaLibrary.coversFolder.appendingPathComponent(name)
        ImageCache.shared.forget(url)
        try? FileManager.default.removeItem(at: url)
        customCovers.removeValue(forKey: key)
    }

    /// Image à afficher : photo choisie, pochette du fichier, image de la vidéo ou miniature en ligne.
    func artwork(_ track: Track) -> String? {
        if let name = customCovers[MediaLibrary.artKey(track.path)] {
            return MediaLibrary.coversFolder.appendingPathComponent(name).absoluteString
        }
        if metas[track.path]?.hasArtwork == true {
            return MediaLibrary.artURL(track.path).absoluteString
        }
        return track.thumbnail
    }

    func subtitle(_ track: Track) -> String {
        var parts: [String] = []
        if track.isAudio {
            parts.append(artist(track))
            if let album = album(track) { parts.append(album) }
        } else {
            if !track.platformName.isEmpty { parts.append(track.platformName) }
            let time = Fmt.duration(duration(track))
            if !time.isEmpty { parts.append(time) }
            let size = Fmt.size(track.filesize)
            if !size.isEmpty { parts.append(size) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Regroupements (Artistes, Albums)

    func artists(_ songs: [Track]) -> [MusicGroup] {
        var groups: [String: [Track]] = [:]
        var names: [String: String] = [:]
        for track in songs {
            let name = artist(track)
            let key = name.lowercased()
            groups[key, default: []].append(track)
            if names[key] == nil { names[key] = name }
        }
        return groups.map { key, tracks in
            let albums = Set(tracks.compactMap { album($0) }).count
            let detail = albums > 0
                ? L("{albums} album(s) · {count} titre(s)", ["albums": "\(albums)", "count": "\(tracks.count)"])
                : L("{count} titre(s)", ["count": "\(tracks.count)"])
            return MusicGroup(id: key, name: names[key] ?? key, subtitle: detail, tracks: sortAlbum(tracks),
                              artwork: tracks.lazy.compactMap { self.artwork($0) }.first)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func albums(_ songs: [Track]) -> [MusicGroup] {
        var groups: [String: [Track]] = [:]
        var titles: [String: String] = [:]
        for track in songs {
            guard let album = album(track) else { continue }
            let key = album.lowercased()
            groups[key, default: []].append(track)
            if titles[key] == nil { titles[key] = album }
        }
        return groups.map { key, tracks in
            let artists = Array(Set(tracks.map { artist($0) })).sorted()
            let by = artists.count == 1 ? artists[0] : L("Artistes divers")
            return MusicGroup(id: key, name: titles[key] ?? key, subtitle: by, tracks: sortAlbum(tracks),
                              artwork: tracks.lazy.compactMap { self.artwork($0) }.first)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func sortAlbum(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            let left = metas[lhs.path]?.trackNumber ?? Int.max
            let right = metas[rhs.path]?.trackNumber ?? Int.max
            if left != right { return left < right }
            return title(lhs).localizedCaseInsensitiveCompare(title(rhs)) == .orderedAscending
        }
    }

    func sortByTitle(_ tracks: [Track]) -> [Track] {
        tracks.sorted { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
    }

    /// Paroles intégrées au fichier (balise « lyrics »), lues à la demande.
    static func lyrics(for track: Track, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: track.fileURL)
            var text = asset.lyrics
            if text == nil || text?.isEmpty == true {
                for format in asset.availableMetadataFormats {
                    for item in asset.metadata(forFormat: format) {
                        let identifier = item.identifier?.rawValue ?? ""
                        if identifier.hasSuffix("USLT") || identifier.hasSuffix("©lyr") || identifier.hasSuffix("%A9lyr") {
                            text = item.stringValue
                        }
                    }
                }
            }
            let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(clean?.isEmpty == false ? clean : nil) }
        }
    }
}

/// Cache d'images (pochettes locales et miniatures en ligne, gardées sur l'iPhone) :
/// décodées en arrière-plan pour que la navigation reste fluide.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let folder: URL
    private var waiting: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 400
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Faxel/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func key(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    func image(_ url: URL) -> UIImage? {
        cache.object(forKey: key(url) as NSString)
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        let name = key(url)
        if let image = cache.object(forKey: name as NSString) {
            completion(image)
            return
        }
        if waiting[name] != nil {
            waiting[name]?.append(completion)
            return
        }
        waiting[name] = [completion]
        let finish: (UIImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let image = image { self.cache.setObject(image, forKey: name as NSString) }
                let callbacks = self.waiting.removeValue(forKey: name) ?? []
                for callback in callbacks { callback(image) }
            }
        }
        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                finish(UIImage(contentsOfFile: url.path)?.preparingForDisplay())
            }
            return
        }
        let disk = folder.appendingPathComponent(MediaLibrary.artKey(name) + ".img")
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = UIImage(contentsOfFile: disk.path) {
                finish(image.preparingForDisplay() ?? image)
                return
            }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data, let image = UIImage(data: data) else {
                    finish(nil)
                    return
                }
                try? data.write(to: disk, options: .atomic)
                finish(image.preparingForDisplay() ?? image)
            }.resume()
        }
    }

    func forget(_ url: URL) {
        cache.removeObject(forKey: key(url) as NSString)
    }
}
