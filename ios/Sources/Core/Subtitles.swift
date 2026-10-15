import Foundation

/// Une ligne de sous-titres (début, fin, texte).
struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

/// Lecture des fichiers de sous-titres .srt, .vtt, .ass et .ssa.
enum SubtitleParser {
    static func load(_ url: URL) -> [SubtitleCue] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""
        let ext = url.pathExtension.lowercased()
        if ext == "ass" || ext == "ssa" {
            return parseASS(text)
        }
        return parse(text)
    }

    /// Sous-titres .ass / .ssa (fréquents pour les séries et les animés).
    static func parseASS(_ raw: String) -> [SubtitleCue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var format: [String] = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var inEvents = false
        var cues: [SubtitleCue] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inEvents = trimmed.lowercased() == "[events]"
                continue
            }
            guard inEvents else { continue }
            if trimmed.lowercased().hasPrefix("format:") {
                format = trimmed.dropFirst(7).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                continue
            }
            guard trimmed.lowercased().hasPrefix("dialogue:") else { continue }
            let body = String(trimmed.dropFirst(9))
            let fields = body.split(separator: ",", maxSplits: max(0, format.count - 1), omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == format.count,
                  let startIndex = format.firstIndex(of: "start"), let endIndex = format.firstIndex(of: "end"),
                  let textIndex = format.firstIndex(of: "text"),
                  let start = time(fields[startIndex]), let end = time(fields[endIndex]) else { continue }
            let content = stripTags(fields[textIndex]
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                cues.append(SubtitleCue(start: start, end: max(end, start + 0.2), text: content))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func parse(_ raw: String) -> [SubtitleCue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [SubtitleCue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = time(parts[0]),
                  let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
            else { continue }
            let body = lines[(timeIndex + 1)...].map(stripTags).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                cues.append(SubtitleCue(start: start, end: max(end, start + 0.2), text: body))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// « 01:02:03,456 », « 02:03.456 » ou « 01:02:03.456 » → secondes.
    static func time(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let pieces = value.split(separator: ":").map(String.init)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        var total = 0.0
        for piece in pieces {
            guard let number = Double(piece) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    private static func stripTags(_ line: String) -> String {
        var output = ""
        var inside = false
        for character in line {
            if character == "<" || character == "{" {
                inside = true
            } else if character == ">" || character == "}" {
                inside = false
            } else if !inside {
                output.append(character)
            }
        }
        return output.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// Texte à afficher au temps donné.
    static func text(at seconds: Double, in cues: [SubtitleCue]) -> String? {
        var low = 0
        var high = cues.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if cues[middle].start <= seconds {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard let index = found else { return nil }
        var lines: [String] = []
        var cursor = index
        while cursor >= 0 && cursor > index - 4 {
            let cue = cues[cursor]
            if cue.start <= seconds && seconds <= cue.end { lines.insert(cue.text, at: 0) }
            cursor -= 1
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - Recherche automatique (films et séries)

    /// Sous-dossiers où les séries rangent souvent leurs sous-titres.
    private static let subtitleFolders: Set<String> = [
        "subs", "sub", "subtitles", "subtitle", "sous-titres", "sous titres", "soustitres", "st", "srt", "vostfr",
    ]

    /// Code d'épisode « S01E02 », « s1e2 », « 1x02 » → (saison, épisode).
    private static let episodePatterns: [NSRegularExpression] = [
        "s(\\d{1,2})[ ._-]?e(\\d{1,3})",
        "(?<![0-9])(\\d{1,2})x(\\d{2,3})(?![0-9])",
        "saison[ ._-]?(\\d{1,2}).*?[ée]pisode[ ._-]?(\\d{1,3})",
        "season[ ._-]?(\\d{1,2}).*?episode[ ._-]?(\\d{1,3})",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func episode(in name: String) -> (season: Int, episode: Int)? {
        let lower = name.lowercased()
        for regex in episodePatterns {
            guard let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let seasonRange = Range(match.range(at: 1), in: lower),
                  let episodeRange = Range(match.range(at: 2), in: lower),
                  let season = Int(lower[seasonRange]), let number = Int(lower[episodeRange]) else { continue }
            return (season, number)
        }
        return nil
    }

    /// Langue devinée d'après le nom du fichier (« .fr. », « French », « VOSTFR », « 3_Eng »…).
    static func language(of url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let tokens = name.split(whereSeparator: { !$0.isLetter }).map(String.init)
        // Les codes courts (« fr », « en », « de »…) ne comptent qu'en fin de nom, pour ne pas
        // confondre avec un mot du titre (« Make.It.Right » n'est pas de l'italien).
        let tail = Set(tokens.suffix(3))
        let words = Set(tokens.filter { $0.count > 3 }).union(tail)
        let table: [(String, [String])] = [
            ("fr", ["fr", "fre", "fra", "french", "francais", "français", "vf", "vff", "vfq", "vostfr", "truefrench"]),
            ("en", ["en", "eng", "english", "anglais"]),
            ("es", ["es", "spa", "esp", "spanish", "espanol", "español", "castellano", "latino"]),
            ("de", ["de", "ger", "deu", "german", "deutsch", "allemand"]),
            ("ru", ["ru", "rus", "russian", "русский"]),
            ("pt", ["pt", "por", "portuguese", "portugues", "português", "br"]),
            ("it", ["it", "ita", "italian", "italiano"]),
            ("ar", ["ar", "ara", "arabic", "arabe"]),
        ]
        for (code, keys) in table where keys.contains(where: { words.contains($0) }) {
            return code
        }
        return nil
    }

    /// Nom lisible pour le menu (« Français », « English (forcés) », ou le nom du fichier).
    static func displayName(_ url: URL) -> String {
        let lower = url.lastPathComponent.lowercased()
        let forced = lower.contains("forced") || lower.contains("forcé")
        let sdh = lower.contains("sdh") || lower.contains(".cc.") || lower.contains("hearing")
        guard let code = language(of: url) else { return url.lastPathComponent }
        var name = Locale(identifier: Lang.code).localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
        if forced { name += " (" + L("forcés") + ")" }
        if sdh { name += " (SDH)" }
        return name + " · " + url.pathExtension.uppercased()
    }

    /// Sous-titres de la vidéo, trouvés tout seuls : même nom (« Film.srt », « Film.fr.srt »),
    /// même épisode (« Serie.S01E02.VOSTFR.srt »), dossier « Subs » / « Sous-titres »…
    /// Les sous-titres dans la langue de l'app passent en premier.
    static func siblings(of video: URL) -> [URL] {
        let manager = FileManager.default
        let folder = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent.lowercased()
        let code = episode(in: base)
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let videosHere = names.filter { videoExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }

        var candidates: [(url: URL, strong: Bool)] = []
        func consider(_ url: URL, insideOwnFolder: Bool) {
            guard subtitleExtensions.contains(url.pathExtension.lowercased()) else { return }
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            if stem == base || stem.hasPrefix(base + ".") || stem.hasPrefix(base + "_") || stem.hasPrefix(base + " ")
                || stem.hasPrefix(base + "-") {
                candidates.append((url, true))
                return
            }
            if let wanted = code {
                if let found = episode(in: stem) {
                    if found.season == wanted.season && found.episode == wanted.episode {
                        candidates.append((url, true))
                    }
                    return
                }
            }
            // Dossier « Subs/Nom de la vidéo/2_English.srt », ou une seule vidéo dans le dossier.
            if insideOwnFolder || videosHere.count <= 1 {
                candidates.append((url, false))
            }
        }

        for name in names {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                consider(url, insideOwnFolder: false)
                continue
            }
            let lower = name.lowercased()
            guard subtitleFolders.contains(lower) || lower == base else { continue }
            let inner = (try? manager.contentsOfDirectory(atPath: url.path)) ?? []
            for item in inner {
                let innerURL = url.appendingPathComponent(item)
                var innerIsDirectory: ObjCBool = false
                guard manager.fileExists(atPath: innerURL.path, isDirectory: &innerIsDirectory) else { continue }
                if innerIsDirectory.boolValue {
                    // Subs/<nom de l'épisode>/…
                    let innerName = item.lowercased()
                    let sameEpisode = code != nil && episode(in: innerName).map { $0 == code! } == true
                    guard innerName == base || sameEpisode else { continue }
                    for file in (try? manager.contentsOfDirectory(atPath: innerURL.path)) ?? [] {
                        consider(innerURL.appendingPathComponent(file), insideOwnFolder: true)
                    }
                } else {
                    consider(innerURL, insideOwnFolder: lower == base)
                }
            }
        }

        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.url.path).inserted }
        let preferred = Lang.code
        func rank(_ item: (url: URL, strong: Bool)) -> Int {
            let lower = item.url.lastPathComponent.lowercased()
            var score = 0
            let found = language(of: item.url)
            if found == preferred {
                score += 0
            } else if found == nil {
                score += 10
            } else if found == "en" {
                score += 20
            } else {
                score += 30
            }
            if lower.contains("forced") || lower.contains("forcé") { score += 5 }
            if lower.contains("sdh") { score += 2 }
            if !item.strong { score += 3 }
            return score
        }
        return unique.sorted { first, second in
            let a = rank(first)
            let b = rank(second)
            return a == b ? first.url.lastPathComponent < second.url.lastPathComponent : a < b
        }
        .map { $0.url }
    }
}
