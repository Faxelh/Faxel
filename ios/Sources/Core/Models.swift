import Foundation

// Lecture tolérante des valeurs JSON venues de Python.
func jsonString(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

func jsonDouble(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
    if let text = value as? String, let double = Double(text), double.isFinite { return double }
    return nil
}

func jsonBool(_ value: Any?) -> Bool {
    if let number = value as? NSNumber { return number.boolValue }
    return false
}

let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]
let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "flac", "aif", "aiff", "caf", "m4b"]
let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]
let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif"]

/// Un fichier de la bibliothèque (vidéo, son ou dossier de photos).
struct Track: Identifiable, Hashable {
    let id: String
    let uid: String?
    let title: String
    let path: String
    let duration: Double?
    let filesize: Double?
    let thumbnail: String?
    let date: String
    let uploader: String
    let platformName: String
    let mediaType: String
    let exists: Bool
    let isFolder: Bool
    /// Lien d'origine (vide pour un fichier ajouté avec 3uTools ou l'app Fichiers).
    let sourceURL: String
    /// Date d'ajout (calculée une seule fois : le tri reste rapide).
    let addedDate: Date
    /// Données d'origine, renvoyées telles quelles au moteur Python.
    let raw: [String: Any]

    init(_ dict: [String: Any]) {
        raw = dict
        uid = jsonString(dict["uid"])
        path = jsonString(dict["filepath"]) ?? ""
        id = uid ?? path
        title = jsonString(dict["title"]) ?? ""
        duration = jsonDouble(dict["duration"])
        filesize = jsonDouble(dict["filesize"])
        let thumb = jsonString(dict["thumbnail"]) ?? ""
        thumbnail = thumb.isEmpty ? nil : thumb
        date = jsonString(dict["date"]) ?? ""
        uploader = jsonString(dict["uploader"]) ?? ""
        platformName = jsonString(dict["platform_name"]) ?? ""
        sourceURL = jsonString(dict["url"]) ?? ""
        addedDate = Fmt.parseDate(date) ?? .distantPast
        var isDirectory: ObjCBool = false
        let present = !path.isEmpty && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if dict["exists"] != nil {
            exists = jsonBool(dict["exists"])
        } else {
            exists = present
        }
        isFolder = dict["is_folder"] != nil ? jsonBool(dict["is_folder"]) : (present && isDirectory.boolValue)
        let ext = (path as NSString).pathExtension.lowercased()
        if let media = jsonString(dict["media_type"]), !media.isEmpty {
            mediaType = media
        } else {
            mediaType = audioExtensions.contains(ext) ? "audio" : "video"
        }
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path && lhs.title == rhs.title && lhs.filesize == rhs.filesize
            && lhs.exists == rhs.exists
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }

    var fileURL: URL { URL(fileURLWithPath: path) }

    var isAudio: Bool { mediaType == "audio" && !isFolder }

    var isVideo: Bool { !isAudio && !isFolder }

    /// Téléchargé depuis Internet (et non copié avec 3uTools / Fichiers).
    var isDownloaded: Bool { !sourceURL.isEmpty || !platformName.isEmpty }



    /// Pour le filtre Vidéos / Audio.
    var kind: String { isFolder ? "photo" : (isAudio ? "audio" : "video") }

    var icon: String {
        if isFolder { return "photo.on.rectangle.angled" }
        return isAudio ? "music.note" : "play.rectangle.fill"
    }

    var meta: String {
        var parts: [String] = []
        if !platformName.isEmpty { parts.append(platformName) }
        let time = Fmt.duration(duration)
        if !time.isEmpty { parts.append(time) }
        let size = Fmt.size(filesize)
        if !size.isEmpty { parts.append(size) }
        if parts.count < 2, let day = date.split(separator: " ").first {
            parts.append(String(day))
        }
        return parts.joined(separator: " · ")
    }

    /// Images d'un dossier de photos (publication TikTok).
    var photoURLs: [URL] {
        guard isFolder else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.sorted()
            .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { fileURL.appendingPathComponent($0) }
    }
}

struct Playlist: Identifiable, Hashable {
    let id: String
    let name: String
    let items: [Track]

    init(_ dict: [String: Any]) {
        id = jsonString(dict["uid"]) ?? UUID().uuidString
        name = jsonString(dict["name"]) ?? "Playlist"
        let raw = dict["items"] as? [[String: Any]] ?? []
        items = raw.map { Track($0) }
    }
}

/// Un téléchargement dans la file du moteur.
struct Job: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let status: String
    let label: String
    let fraction: Double
    let speed: Double?
    let eta: Double?
    let message: String
    let thumbnail: String?
    let active: Bool
    let mediaType: String
    let quality: String
    let platformName: String
    let filepath: String?

    init(_ dict: [String: Any]) {
        id = jsonString(dict["id"]) ?? UUID().uuidString
        url = jsonString(dict["url"]) ?? ""
        title = jsonString(dict["title"]) ?? url
        status = jsonString(dict["status"]) ?? ""
        label = jsonString(dict["label"]) ?? ""
        fraction = jsonDouble(dict["fraction"]) ?? 0
        speed = jsonDouble(dict["speed"])
        eta = jsonDouble(dict["eta"])
        message = jsonString(dict["message"]) ?? ""
        let thumb = jsonString(dict["thumbnail"]) ?? ""
        thumbnail = thumb.isEmpty ? nil : thumb
        active = jsonBool(dict["active"])
        mediaType = jsonString(dict["media_type"]) ?? "video"
        quality = jsonString(dict["quality"]) ?? ""
        platformName = jsonString(dict["platform_name"]) ?? ""
        let path = jsonString(dict["filepath"]) ?? ""
        filepath = path.isEmpty ? nil : path
    }

    var isPaused: Bool { status == "paused" }
    var isFailed: Bool { status == "failed" }
    var isDone: Bool { status == "done" }
    var isSkipped: Bool { status == "skipped" }
    var isCancelled: Bool { status == "cancelled" }

    var info: String {
        let media = mediaType == "audio" ? L("Audio") : qualityLabel(quality.isEmpty ? "Meilleure" : quality)
        return platformName.isEmpty ? media : platformName + " · " + media
    }

    var statusText: String {
        var parts = [statusLabel(label.isEmpty ? status : label)]
        if status == "downloading" {
            parts.append("\(Int(fraction * 100)) %")
            let speedText = Fmt.speed(speed)
            if !speedText.isEmpty { parts.append(speedText) }
            if let eta = eta, eta > 0 {
                parts.append(L("reste {eta}", ["eta": Fmt.clock(eta)]))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Libellé d'état du moteur (en français) dans la langue de l'app.
func statusLabel(_ label: String) -> String {
    if label.hasPrefix("Nouvelle tentative ("),
       let start = label.firstIndex(of: "("), let end = label.firstIndex(of: ")"), start < end {
        let count = String(label[label.index(after: start)..<end])
        return L("Nouvelle tentative ({count})…", ["count": count])
    }
    return L(label)
}

func qualityLabel(_ key: String) -> String {
    key == "Meilleure" ? L("Meilleure") : key
}

/// Résultat de l'analyse d'un lien (écran Télécharger).
struct Analysis {
    struct Entry: Hashable {
        let url: String
        let title: String
    }

    let kind: String
    let url: String
    let title: String
    let uploader: String
    let duration: Double?
    let thumbnail: String?
    let qualities: [String]
    let audioOK: Bool
    let videoOK: Bool
    let entries: [Entry]
    let photoCount: Int
    let hasMusic: Bool
    let platformName: String
    /// Vidéo regardée dans une playlist (ou un Mix YouTube) : lien de la playlist entière.
    let playlistURL: String

    init(_ dict: [String: Any]) {
        kind = jsonString(dict["kind"]) ?? "video"
        url = jsonString(dict["url"]) ?? ""
        title = jsonString(dict["title"]) ?? ""
        uploader = jsonString(dict["uploader"]) ?? ""
        duration = jsonDouble(dict["duration"])
        let thumb = jsonString(dict["thumbnail"]) ?? ""
        thumbnail = thumb.isEmpty ? nil : thumb
        qualities = (dict["qualities"] as? [Any] ?? []).compactMap { jsonString($0) }
        audioOK = dict["audio_ok"] == nil ? true : jsonBool(dict["audio_ok"])
        videoOK = dict["video_ok"] == nil ? true : jsonBool(dict["video_ok"])
        entries = (dict["entries"] as? [[String: Any]] ?? []).compactMap { (entry: [String: Any]) -> Entry? in
            guard let link = jsonString(entry["url"]), !link.isEmpty else { return nil }
            return Entry(url: link, title: jsonString(entry["title"]) ?? link)
        }
        photoCount = Int(jsonDouble(dict["photo_count"]) ?? 0)
        hasMusic = jsonBool(dict["has_music"])
        platformName = jsonString(dict["platform_name"]) ?? ""
        playlistURL = jsonString(dict["playlist_url"]) ?? ""
    }

    var details: String {
        var parts: [String] = []
        switch kind {
        case "playlist":
            parts.append(L("Playlist · {count} vidéo(s)", ["count": "\(entries.count)"]))
        case "photo":
            parts.append(L("{count} photo(s)", ["count": "\(photoCount)"]))
            if hasMusic { parts.append(L("avec musique")) }
        default:
            if !uploader.isEmpty { parts.append(uploader) }
            let time = Fmt.duration(duration)
            if !time.isEmpty { parts.append(time) }
            if !platformName.isEmpty { parts.append(platformName) }
        }
        return parts.joined(separator: " · ")
    }
}

/// Résultat d'une recherche YouTube.
struct WebResult: Identifiable, Hashable {
    let id: String
    let url: String
    let title: String
    let uploader: String
    let duration: Double?
    let thumbnail: String?
    let views: Double?

    init(_ dict: [String: Any]) {
        url = jsonString(dict["url"]) ?? ""
        id = url
        title = jsonString(dict["title"]) ?? url
        uploader = jsonString(dict["uploader"]) ?? ""
        duration = jsonDouble(dict["duration"])
        let thumb = jsonString(dict["thumbnail"]) ?? ""
        thumbnail = thumb.isEmpty ? nil : thumb
        views = jsonDouble(dict["view_count"])
    }

    var meta: String {
        var parts: [String] = []
        if !uploader.isEmpty { parts.append(uploader) }
        let time = Fmt.duration(duration)
        if !time.isEmpty { parts.append(time) }
        if let views = views, views > 0 { parts.append(L("{count} vues", ["count": Fmt.count(views)])) }
        return parts.joined(separator: " · ")
    }
}

/// Écrans de la Bibliothèque.
enum LibraryRoute: Hashable, Codable {
    case playlists
    case artists
    case albums
    case songs
    case videos
    case downloads
    case favorites
    case vault
    case files(String)
    case playlist(String)
    case artist(String)
    case album(String)
    case virtualFolders
    case virtualFolder(String)
}

enum AppTab: String, Hashable {
    case home, library, download, settings, browser
}
