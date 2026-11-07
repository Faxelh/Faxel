import AVFoundation
import Speech

/// Transcription locale du système, exécutée sur l'appareil quand iOS la prend en charge.
enum AISubtitleGenerator {
    private static var activeTask: SFSpeechRecognitionTask?
    private struct CuePart {
        let start: Double
        let duration: Double
        let text: String
    }
    private struct AudioChunk {
        let url: URL
        let offset: Double
    }
    enum Failure: LocalizedError {
        case unsupportedLanguage
        case permissionDenied
        case audioExtraction
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: return "Le modèle de reconnaissance hors ligne n'est pas disponible pour cette langue sur cet iPhone."
            case .permissionDenied: return "Autorisez la reconnaissance vocale de Faxel dans Réglages pour générer les sous-titres."
            case .audioExtraction: return "Faxel n'a pas pu extraire le son de cette vidéo."
            case .noSpeech: return "Aucune parole n'a été reconnue dans cette vidéo."
            }
        }
    }

    static func generate(from videoURL: URL, localeIdentifier: String, completion: @escaping (Result<URL, Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { completion(.failure(Failure.permissionDenied)) }
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
                  recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                DispatchQueue.main.async { completion(.failure(Failure.unsupportedLanguage)) }
                return
            }
            let asset = AVURLAsset(url: videoURL)
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0 else {
                DispatchQueue.main.async { completion(.failure(Failure.audioExtraction)) }
                return
            }
            extractChunks(from: asset, total: duration, completion: { result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let chunks): transcribe(chunks, index: 0, recognizer: recognizer, parts: [], completion: completion)
                }
            })
        }
    }

    /// Segments d'au plus 45 s évitent les limites de durée des requêtes Speech.
    private static func extractChunks(from asset: AVAsset, total: Double, start: Double = 0,
                                      chunks: [AudioChunk] = [], completion: @escaping (Result<[AudioChunk], Error>) -> Void) {
        guard start < total else {
            completion(.success(chunks))
            return
        }
        let length = min(45, total - start)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("faxel-audio-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            cleanup(chunks)
            completion(.failure(Failure.audioExtraction))
            return
        }
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        exporter.exportAsynchronously {
            guard exporter.status == .completed else {
                try? FileManager.default.removeItem(at: output)
                cleanup(chunks)
                DispatchQueue.main.async { completion(.failure(exporter.error ?? Failure.audioExtraction)) }
                return
            }
            let next = chunks + [AudioChunk(url: output, offset: start)]
            extractChunks(from: asset, total: total, start: start + length, chunks: next, completion: completion)
        }
    }

    private static func transcribe(_ chunks: [AudioChunk], index: Int, recognizer: SFSpeechRecognizer,
                                   parts: [CuePart], completion: @escaping (Result<URL, Error>) -> Void) {
        guard chunks.indices.contains(index) else {
            guard !parts.isEmpty else {
                cleanup(chunks)
                DispatchQueue.main.async { completion(.failure(Failure.noSpeech)) }
                return
            }
            writeSubtitles(parts, chunks: chunks, completion: completion)
            return
        }
        let chunk = chunks[index]
        let request = SFSpeechURLRecognitionRequest(url: chunk.url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        activeTask = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                activeTask = nil
                cleanup(chunks)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let result, result.isFinal else { return }
            activeTask = nil
            try? FileManager.default.removeItem(at: chunk.url)
            let nextParts = parts + result.bestTranscription.segments.map {
                CuePart(start: chunk.offset + $0.timestamp, duration: $0.duration, text: $0.substring)
            }
            transcribe(chunks, index: index + 1, recognizer: recognizer, parts: nextParts, completion: completion)
        }
    }

    private static func writeSubtitles(_ parts: [CuePart], chunks: [AudioChunk], completion: @escaping (Result<URL, Error>) -> Void) {
        let ordered = parts.sorted { $0.start < $1.start }
        let groups = subtitleGroups(ordered)
        let content = groups.enumerated().map { index, group in
            let first = group[0]
            let last = group[group.count - 1]
            let text = group.map(\.text).joined(separator: " ")
            return "\(index + 1)\n\(time(first.start)) --> \(time(last.start + max(last.duration, 0.25)))\n\(text)"
        }.joined(separator: "\n\n") + "\n"
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("faxel-\(UUID().uuidString).srt")
        do {
            try Data(content.utf8).write(to: output, options: .atomic)
            cleanup(chunks)
            DispatchQueue.main.async { completion(.success(output)) }
        } catch {
            cleanup(chunks)
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    private static func subtitleGroups(_ parts: [CuePart]) -> [[CuePart]] {
        var groups: [[CuePart]] = []
        var current: [CuePart] = []
        for part in parts {
            if let first = current.first {
                let previous = current.last!
                let textLength = current.reduce(0) { $0 + $1.text.count } + part.text.count
                let endsSentence = previous.text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?…")) != nil
                let tooLong = part.start - first.start > 4.2 || textLength > 52
                if endsSentence || tooLong {
                    groups.append(current)
                    current = []
                }
            }
            current.append(part)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func cleanup(_ chunks: [AudioChunk]) {
        chunks.forEach { try? FileManager.default.removeItem(at: $0.url) }
    }

    private static func time(_ seconds: Double) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let secs = (milliseconds / 1_000) % 60
        let millis = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}
