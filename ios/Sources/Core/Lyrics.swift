import AVFoundation
import CryptoKit
import Foundation

/// Une ligne de paroles (time = nil pour des paroles non synchronisées).
struct LyricLine: Identifiable, Equatable {
    let id: Int
    var time: Double?
    var text: String
}

/// Paroles d'un morceau.
struct Lyrics: Equatable {
    enum Source: String {
        case saved, file, embedded, online
    }

    var lines: [LyricLine]
    var source: Source

    var isSynced: Bool { lines.contains { $0.time != nil } }

    /// Index de la ligne chantée au temps donné.
    func currentIndex(at seconds: Double) -> Int? {
        var found: Int?
        for (offset, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= seconds + 0.15 { found = offset } else { break }
        }
        return found
    }

    var lrc: String {
        lines.map { line in
            guard let time = line.time else { return line.text }
            let minutes = Int(time / 60)
            return String(format: "[%02d:%05.2f]", minutes, time - Double(minutes * 60)) + line.text
        }.joined(separator: "\n")
    }
}

enum LyricsParser {
    /// Lit du LRC (synchronisé) ou du texte simple.
    static func parse(_ raw: String) -> [LyricLine] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var timed: [(Double, String)] = []
        var plain: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                if let seconds = time(String(tag)) {
                    times.append(seconds)
                    line = line[line.index(after: close)...]
                } else {
                    line = ""
                    break
                }
            }
            let content = line.trimmingCharacters(in: .whitespaces)
            if times.isEmpty {
                if !rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("[") { plain.append(content) }
            } else {
                for value in times { timed.append((value, content)) }
            }
        }
        if !timed.isEmpty {
            return timed.sorted { $0.0 < $1.0 }.enumerated()
                .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
        }
        while plain.first?.isEmpty == true { plain.removeFirst() }
        while plain.last?.isEmpty == true { plain.removeLast() }
        return plain.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
    }

    static func time(_ tag: String) -> Double? {
        let parts = tag.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// Résultat de la recherche en ligne (LRCLIB, base libre de paroles).
struct OnlineLyrics: Identifiable, Hashable {
    let id: Int
    let track: String
    let artist: String
    let duration: Double
    let synced: String?
    let plain: String?

    var hasSynced: Bool { !(synced ?? "").isEmpty }
}

/// Paroles des morceaux : gardées dans Faxel, fichier .lrc à côté du son,
/// balise du fichier, ou recherche en ligne (synchronisées si possible).
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var trackPath: String?
    @Published private(set) var loading = false
    @Published private(set) var results: [OnlineLyrics] = []
    @Published private(set) var searching = false
    @Published private(set) var searched = false

    private static var folder: URL {
        let url = PythonEngine.dataURL.appendingPathComponent("lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func savedURL(_ track: Track) -> URL {
        let digest = SHA256.hash(data: Data(track.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(String(digest.prefix(32)) + ".lrc")
    }

    func load(_ track: Track, autoSearch: Bool) {
        guard trackPath != track.path else { return }
        trackPath = track.path
        lyrics = nil
        results = []
        searched = false
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LyricsStore.localLyrics(track)
            DispatchQueue.main.async {
                guard self.trackPath == track.path else { return }
                self.lyrics = found
                self.loading = false
                if found == nil && autoSearch {
                    self.fetchBest(track)
                }
            }
        }
    }

    private static func localLyrics(_ track: Track) -> Lyrics? {
        if let text = try? String(contentsOf: savedURL(track), encoding: .utf8) {
            let lines = LyricsParser.parse(text)
            if !lines.isEmpty { return Lyrics(lines: lines, source: .saved) }
        }
        let sibling = track.fileURL.deletingPathExtension().appendingPathExtension("lrc")
        if let text = (try? String(contentsOf: sibling, encoding: .utf8)) ?? (try? String(contentsOf: sibling, encoding: .isoLatin1)) {
            let lines = LyricsParser.parse(text)
            if !lines.isEmpty { return Lyrics(lines: lines, source: .file) }
        }
        let asset = AVURLAsset(url: track.fileURL)
        var text = asset.lyrics
        if text == nil || text?.isEmpty == true {
            for format in asset.availableMetadataFormats {
                for item in asset.metadata(forFormat: format) {
                    let identifier = item.identifier?.rawValue ?? ""
                    if identifier.hasSuffix("USLT") || identifier.hasSuffix("%A9lyr") || identifier.hasSuffix("©lyr") {
                        text = item.stringValue
                    }
                }
            }
        }
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Lyrics(lines: LyricsParser.parse(text), source: .embedded)
        }
        return nil
    }

    func save(_ lyrics: Lyrics, for track: Track) {
        try? lyrics.lrc.write(to: LyricsStore.savedURL(track), atomically: true, encoding: .utf8)
        if trackPath == track.path { self.lyrics = lyrics }
    }

    func delete(for track: Track) {
        try? FileManager.default.removeItem(at: LyricsStore.savedURL(track))
        trackPath = nil
        load(track, autoSearch: false)
    }

    // MARK: En ligne (LRCLIB)

    /// « Artiste - Titre (Official Video) » → (titre, artiste).
    static func guess(_ track: Track) -> (title: String, artist: String?) {
        let library = MediaLibrary.shared
        var title = cleanTitle(library.title(track))
        var artist = library.knownArtist(track)
        if let dash = title.range(of: " - ") {
            let left = String(title[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(title[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty && !right.isEmpty {
                if artist == nil || artist?.lowercased().contains("vevo") == true || artist == left { artist = left }
                title = right
            }
        }
        if let comma = artist?.range(of: ",") {
            artist = String(artist![..<comma.lowerBound])
        }
        return (title, artist?.replacingOccurrences(of: "VEVO", with: ""))
    }

    static func cleanTitle(_ title: String) -> String {
        var text = title
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open),
                  let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        for marker in [" feat", " ft.", " ft ", "|"] {
            if let found = text.range(of: marker, options: .caseInsensitive) {
                text = String(text[..<found.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func request(_ items: [URLQueryItem]) -> URLRequest? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Faxel iOS 1.0 (https://github.com/Faxelh)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func decode(_ data: Data) -> [OnlineLyrics] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            let synced = item["syncedLyrics"] as? String
            let plain = item["plainLyrics"] as? String
            guard !(synced ?? "").isEmpty || !(plain ?? "").isEmpty else { return nil }
            return OnlineLyrics(id: id, track: item["trackName"] as? String ?? "",
                                artist: item["artistName"] as? String ?? "",
                                duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0,
                                synced: synced, plain: plain)
        }
    }

    func search(_ track: Track, query: String? = nil, completion: (() -> Void)? = nil) {
        let guess = LyricsStore.guess(track)
        var items: [URLQueryItem]
        if let query = query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            items = [URLQueryItem(name: "q", value: query)]
        } else {
            items = [URLQueryItem(name: "track_name", value: guess.title)]
            if let artist = guess.artist, !artist.isEmpty {
                items.append(URLQueryItem(name: "artist_name", value: artist))
            }
        }
        guard let request = LyricsStore.request(items) else { return }
        let duration = MediaLibrary.shared.duration(track) ?? 0
        searching = true
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var found = data.map { LyricsStore.decode($0) } ?? []
            found.sort { lhs, rhs in
                if lhs.hasSynced != rhs.hasSynced { return lhs.hasSynced }
                return abs(lhs.duration - duration) < abs(rhs.duration - duration)
            }
            DispatchQueue.main.async {
                self.searching = false
                self.searched = true
                self.results = found
                completion?()
            }
        }.resume()
    }

    /// Recherche automatique, puis sans l'artiste si rien n'est trouvé.
    func fetchBest(_ track: Track) {
        let duration = MediaLibrary.shared.duration(track) ?? 0
        search(track) { [weak self] in
            guard let self = self, self.trackPath == track.path, self.lyrics == nil else { return }
            if let best = self.results.first,
               duration <= 0 || best.duration <= 0 || abs(best.duration - duration) < 8 {
                self.use(best, for: track)
            } else if self.results.isEmpty {
                self.search(track, query: LyricsStore.guess(track).title) {
                    guard self.trackPath == track.path, self.lyrics == nil, let best = self.results.first,
                          duration <= 0 || best.duration <= 0 || abs(best.duration - duration) < 5 else { return }
                    self.use(best, for: track)
                }
            }
        }
    }

    func use(_ result: OnlineLyrics, for track: Track) {
        let text = result.hasSynced ? (result.synced ?? "") : (result.plain ?? "")
        let lines = LyricsParser.parse(text)
        guard !lines.isEmpty else { return }
        save(Lyrics(lines: lines, source: .online), for: track)
    }
}
