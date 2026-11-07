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
            PHPhotoLibrary.shared().performChanges({
                if let video = video {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
                }
                for image in images {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: image)
                }
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success, success ? nil : (error?.localizedDescription ?? "Photos a refusé l'enregistrement."))
                }
            })
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
            PHPhotoLibrary.shared().performChanges({
                for video in videos {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
                }
                for image in images {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: image)
                }
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success, success ? nil : (error?.localizedDescription ?? "Photos a refusé l'enregistrement."))
                }
            })
        }
    }
}

/// Compression des vidéos (720p) et des sons (AAC) avec AVFoundation.
enum MediaCompressor {
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
