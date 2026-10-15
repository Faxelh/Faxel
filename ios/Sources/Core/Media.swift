import AVFoundation
import Photos
import UIKit

/// Ajout à l'app Photos (vidéos et photos).
enum PhotoSaver {
    static func save(video: URL?, images: [URL], completion: @escaping (Bool) -> Void) {
        guard video != nil || !images.isEmpty else {
            completion(false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if let video = video {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
                }
                for image in images {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: image)
                }
            }, completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            })
        }
    }
}

/// Compression des vidéos (720p) et des sons (AAC) avec AVFoundation.
enum MediaCompressor {
    static func compressVideo(source: URL, target: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: source)
        var preset = AVAssetExportPresetMediumQuality
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            if min(abs(size.width), abs(size.height)) > 720 {
                preset = AVAssetExportPreset1280x720
            }
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(false)
            return
        }
        export.outputURL = target
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            let ok = export.status == .completed
            DispatchQueue.main.async { completion(ok) }
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
