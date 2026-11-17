import AVFoundation
import Photos
import UIKit

/// Ajout à l'app Photos (vidéos et photos).
enum PhotoSaver {
    static func save(video: URL?, images: [URL], completion: @escaping (Bool, String?) -> Void) {
        guard video != nil || !images.isEmpty else {
            completion(false, "Aucun fichier photo ou vidéo compatible.")
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false, "Autorisation Photos : \(status). Vérifiez Réglages > Apps > Faxel > Photos.") }
                return
            }
            performChange(videos: video.map { [$0] } ?? [], images: images, completion: completion)
        }
    }
}

extension PhotoSaver {
    /// Plusieurs vidéos et photos en une fois.
    static func saveMany(videos: [URL], images: [URL], completion: @escaping (Bool, String?) -> Void) {
        guard !videos.isEmpty || !images.isEmpty else {
            completion(false, "Aucun fichier photo ou vidéo compatible.")
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false, "Autorisation Photos : \(status). Vérifiez Réglages > Apps > Faxel > Photos.") }
                return
            }
            performChange(videos: videos, images: images, completion: completion)
        }
    }

    /// PhotoKit's older convenience constructors can fail on local downloads on
    /// recent iOS versions (including error 3302). Explicit resource requests
    /// preserve the source file and report which item could not be imported.
    private static func performChange(videos: [URL], images: [URL], allowVideoRepair: Bool = true,
                                      completion: @escaping (Bool, String?) -> Void) {
        let files = videos + images
        guard let missing = files.first(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) else {
            PHPhotoLibrary.shared().performChanges({
                for video in videos {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .video, fileURL: video, options: options)
                }
                for image in images {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .photo, fileURL: image, options: options)
                }
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    guard !success, let error = error as NSError? else {
                        completion(success, success ? nil : "Photos a refusé l'enregistrement.")
                        return
                    }
                    if allowVideoRepair, videos.count == 1, images.isEmpty,
                       error.domain == "PHPhotosErrorDomain", error.code == 3302 {
                        Self.repairVideoForPhotos(videos[0]) { repaired, repairError in
                            guard let repaired = repaired else {
                                completion(false, repairError ?? error.localizedDescription)
                                return
                            }
                            Self.performChange(videos: [repaired], images: [], allowVideoRepair: false) { ok, message in
                                try? FileManager.default.removeItem(at: repaired)
                                completion(ok, message)
                            }
                        }
                        return
                    }
                    let itemName = files.first?.lastPathComponent ?? "fichier"
                    let details = error.code == 3302
                        ? "Photos a refusé « \(itemName) » (erreur 3302). Le fichier original reste dans la bibliothèque Faxel. Vérifiez l’espace disponible et l’accès de Faxel dans Réglages > Confidentialité et sécurité > Photos."
                        : "Impossible d’ajouter « \(itemName) » à Photos (\(error.code)) : \(error.localizedDescription)"
                    completion(false, details)
                }
            })
            return
        }
        DispatchQueue.main.async { completion(false, "Fichier inaccessible : \(missing.lastPathComponent).") }
    }

    /// Photos code 3302 means the resource failed validation. Re-export to a
    /// standard H.264/AAC container once, then retry the import without touching
    /// the user's original download.
    private static func repairVideoForPhotos(_ source: URL, completion: @escaping (URL?, String?) -> Void) {
        let asset = AVURLAsset(url: source)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        // Retenter avec un profil H.264 moins lourd et compatible Photos avant
        // la qualité maximale, qui peut durer longtemps sur les vidéos longues.
        let preset = [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality, AVAssetExportPresetHighestQuality]
            .first(where: { presets.contains($0) })
        guard let preset, let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(nil, "Photos refuse ce format vidéo et Faxel n'a pas pu le convertir.")
            return
        }
        let type: AVFileType = export.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        guard export.supportedFileTypes.contains(type) else {
            completion(nil, "Aucun format compatible avec Photos n'est disponible pour cette vidéo.")
            return
        }
        let ext = type == .mp4 ? "mp4" : "mov"
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaxelPhotos-\(UUID().uuidString).\(ext)")
        export.outputURL = target
        export.outputFileType = type
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            DispatchQueue.main.async {
                guard export.status == .completed else {
                    try? FileManager.default.removeItem(at: target)
                    completion(nil, export.error?.localizedDescription ?? "La conversion vidéo a échoué.")
                    return
                }
                completion(target, nil)
            }
        }
    }
}

/// Compression des vidéos (720p) et des sons (AAC) avec AVFoundation.
enum MediaCompressor {
    /// Coupe un extrait ou retire une portion d'un fichier audio en conservant le reste.
    static func editAudio(source: URL, target: URL, start: Double, end: Double, removeSelection: Bool,
                          progress: ((Double) -> Void)? = nil,
                          exportSession: ((AVAssetExportSession) -> Void)? = nil,
                          completion: @escaping (Result<Void, Error>) -> Void) {
        let asset = AVURLAsset(url: source)
        guard let sourceTrack = asset.tracks(withMediaType: .audio).first else {
            completion(.failure(NSError(domain: "FaxelAudioEdit", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: L("Aucune piste audio utilisable dans ce fichier.")])) )
            return
        }
        let total = asset.duration.seconds
        guard total.isFinite, total > 0, start.isFinite, end.isFinite,
              start >= 0, end <= total, end - start >= 0.25,
              (!removeSelection || total - (end - start) >= 0.25) else {
            completion(.failure(NSError(domain: "FaxelAudioEdit", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: L("La plage audio sélectionnée n'est pas valide.")])) )
            return
        }
        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(NSError(domain: "FaxelAudioEdit", code: 3,
                                        userInfo: [NSLocalizedDescriptionKey: L("Faxel n'a pas pu préparer le montage audio.")])) )
            return
        }
        let scale = max(asset.duration.timescale, 600)
        let startTime = CMTime(seconds: start, preferredTimescale: scale)
        let endTime = CMTime(seconds: end, preferredTimescale: scale)
        do {
            if removeSelection {
                if startTime > .zero {
                    try outputTrack.insertTimeRange(CMTimeRange(start: .zero, duration: startTime), of: sourceTrack, at: .zero)
                }
                let tailDuration = asset.duration - endTime
                if tailDuration > .zero {
                    let insertion = startTime
                    try outputTrack.insertTimeRange(CMTimeRange(start: endTime, duration: tailDuration), of: sourceTrack, at: insertion)
                }
            } else {
                try outputTrack.insertTimeRange(CMTimeRange(start: startTime, duration: endTime - startTime),
                                                of: sourceTrack, at: .zero)
            }
        } catch {
            completion(.failure(error))
            return
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A),
              export.supportedFileTypes.contains(.m4a) else {
            completion(.failure(NSError(domain: "FaxelAudioEdit", code: 4,
                                        userInfo: [NSLocalizedDescriptionKey: L("L'export audio M4A n'est pas disponible sur cet appareil.")])) )
            return
        }
        export.outputURL = target
        export.outputFileType = .m4a
        export.shouldOptimizeForNetworkUse = true
        exportSession?(export)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async { progress?(Double(export.progress)) }
        }
        export.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate()
                if export.status == .completed {
                    progress?(1)
                    completion(.success(()))
                } else {
                    try? FileManager.default.removeItem(at: target)
                    completion(.failure(export.error ?? NSError(domain: "FaxelAudioEdit", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: L("La modification audio a échoué.")])) )
                }
            }
        }
    }

    static func extractAudio(source: URL, target: URL, start: Double, end: Double?,
                             progress: ((Double) -> Void)? = nil,
                             exportSession: ((AVAssetExportSession) -> Void)? = nil,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        let asset = AVURLAsset(url: source)
        guard asset.tracks(withMediaType: .audio).first != nil,
              AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPresetAppleM4A),
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A),
              export.supportedFileTypes.contains(.m4a) else {
            completion(.failure(NSError(domain: "FaxelAudioExtract", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: L("Cette vidéo ne contient pas de piste audio compatible.")])))
            return
        }
        let startTime = CMTime(seconds: max(0, start), preferredTimescale: 600)
        if let end = end, end > start {
            export.timeRange = CMTimeRange(start: startTime, duration: CMTime(seconds: end - start, preferredTimescale: 600))
        }
        export.outputURL = target
        export.outputFileType = .m4a
        export.shouldOptimizeForNetworkUse = true
        exportSession?(export)
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async { progress?(Double(export.progress)) }
        }
        export.exportAsynchronously {
            DispatchQueue.main.async {
                progressTimer.invalidate()
                if export.status == .completed {
                    progress?(1)
                    completion(.success(()))
                } else {
                    try? FileManager.default.removeItem(at: target)
                    let failure = export.error ?? NSError(
                        domain: "FaxelAudioExtract",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: L("La conversion vidéo vers audio a échoué.")]
                    )
                    completion(.failure(failure))
                }
            }
        }
    }

    static func compressVideo(source: URL, target: URL,
                              presetName requestedPreset: String = AVAssetExportPreset1280x720,
                              progress: ((Double) -> Void)? = nil,
                              completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: source)
        var preset = requestedPreset
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            let shortEdge = min(abs(size.width), abs(size.height))
            if preset == AVAssetExportPreset1280x720 && shortEdge <= 720 {
                preset = AVAssetExportPresetMediumQuality
            } else if preset == AVAssetExportPreset960x540 && shortEdge <= 540 {
                preset = AVAssetExportPresetMediumQuality
            } else if preset == AVAssetExportPreset640x480 && shortEdge <= 480 {
                preset = AVAssetExportPresetLowQuality
            }
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(false)
            return
        }
        export.outputURL = target
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async { progress?(Double(export.progress)) }
        }
        export.exportAsynchronously {
            let ok = export.status == .completed
            DispatchQueue.main.async {
                progressTimer.invalidate()
                if ok { progress?(1) }
                completion(ok)
            }
        }
    }

    static func compressAudio(source: URL, target: URL, bitrate: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let finish: (Bool) -> Void = { ok in
                DispatchQueue.main.async { completion(ok) }
            }
            let asset = AVURLAsset(url: source)
            guard let track = asset.tracks(withMediaType: .audio).first,
                  let reader = try? AVAssetReader(asset: asset),
                  let writer = try? AVAssetWriter(outputURL: target, fileType: .m4a) else {
                finish(false)
                return
            }
            let pcm: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                finish(false)
                return
            }
            reader.add(output)
            let aac: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: bitrate,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                finish(false)
                return
            }
            writer.add(input)
            guard reader.startReading(), writer.startWriting() else {
                finish(false)
                return
            }
            writer.startSession(atSourceTime: .zero)
            let queue = DispatchQueue(label: "faxel.compress")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let buffer = output.copyNextSampleBuffer() {
                        if !input.append(buffer) {
                            input.markAsFinished()
                            reader.cancelReading()
                            writer.cancelWriting()
                            finish(false)
                            return
                        }
                    } else {
                        input.markAsFinished()
                        let readOK = reader.status == .completed
                        writer.finishWriting {
                            finish(readOK && writer.status == .completed)
                        }
                        return
                    }
                }
            }
        }
    }
}
