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
    private static func performChange(videos: [URL], images: [URL], completion: @escaping (Bool, String?) -> Void) {
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
}

/// Compression des vidéos (720p) et des sons (AAC) avec AVFoundation.
enum MediaCompressor {
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
                    completion(.failure(export.error ?? NSError(domain: "FaxelAudioExtract", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: L("La conversion vidéo vers audio a échoué.")]))))
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
