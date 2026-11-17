import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Sélectionne une vidéo, sa qualité cible puis démarre une copie compressée.
struct CompressionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath = ""
    @State private var selectedPreset = AVAssetExportPreset1280x720
    @State private var sourceTab = 0
    @State private var photoVideos: [PHAsset] = []
    @State private var photosAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var selectedPhoto: PhotoAssetSelection?
    @State private var chosenPhoto: PHAsset?

    private let presets: [(name: String, value: String, factor: Double)] = [
        ("1080p", AVAssetExportPreset1920x1080, 0.72),
        ("720p", AVAssetExportPreset1280x720, 0.48),
        ("540p", AVAssetExportPreset960x540, 0.32),
        ("480p", AVAssetExportPreset640x480, 0.25),
    ]

    private var selectedTrack: Track? { model.videos.first { $0.path == selectedPath } }
    private var selectedQuality: (name: String, value: String, factor: Double) {
        presets.first { $0.value == selectedPreset } ?? presets[1]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker(L("Source"), selection: Binding(
                        get: { sourceTab },
                        set: { value in
                            guard value != sourceTab else { return }
                            sourceTab = value
                            selectedPath = ""
                            chosenPhoto = nil
                            selectedPhoto = nil
                        }
                    )) {
                        Text(L("Photos")).tag(0)
                        Text(L("Vidéos de l'app")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if sourceTab == 0 {
                        photosGrid
                        if let chosenPhoto {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(photoAssetName(chosenPhoto))
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(2)
                                Text(L("Taille actuelle : {size}", ["size": Fmt.size(photoAssetSize(chosenPhoto))]))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    } else {
                    HStack(spacing: 12) {
                        Label(L("Vidéos"), systemImage: "video.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Picker(L("Qualité"), selection: $selectedPreset) {
                            ForEach(presets, id: \.value) { preset in
                                Text(preset.name).tag(preset.value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    if model.videos.isEmpty {
                        EmptyState(icon: "film", title: L("Aucune vidéo à compresser"), subtitle: "")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 14) {
                            ForEach(model.videos) { track in
                                videoCard(track)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if let track = selectedTrack {
                        let sourceSize = fileSize(track.path)
                        let estimate = sourceSize * selectedQuality.factor
                        VStack(alignment: .leading, spacing: 10) {
                            Text(track.title).font(.system(size: 16, weight: .bold)).lineLimit(2)
                            HStack {
                                Text(L("Taille actuelle : {size}", ["size": Fmt.size(sourceSize)]))
                                Spacer()
                                Text(L("Estimée : {size}", ["size": Fmt.size(estimate)]))
                                    .foregroundStyle(Color.brand)
                            }
                            .font(.system(size: 12))
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                    } else if !model.videos.isEmpty {
                        Text(L("Choisissez une vidéo pour voir les options de compression."))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("Compresser une vidéo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fermer")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                compressionAction
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Une nouvelle ouverture commence sans vidéo présélectionnée. Le choix
            // de l'onglet « Vidéos de l'app » ne lance donc jamais une compression
            // sur un ancien élément sélectionné.
            sourceTab = 0
            selectedPath = ""
            chosenPhoto = nil
            selectedPhoto = nil
            loadPhotos()
        }
        .sheet(item: $selectedPhoto) { selection in
            PhotoCompressionSheet(asset: selection.asset)
        }
    }

    private var compressionAction: some View {
        let selected = sourceTab == 0 ? chosenPhoto != nil : selectedTrack != nil
        let busy = selectedTrack.map { model.compressing.contains($0.path) } ?? false
        return Button {
            if sourceTab == 0, let chosenPhoto {
                selectedPhoto = PhotoAssetSelection(asset: chosenPhoto)
            } else if sourceTab == 1, let track = selectedTrack {
                model.compress(track, videoPreset: selectedPreset)
            }
        } label: {
            HStack(spacing: 9) {
                if busy { ProgressView().tint(.white) }
                else { Image(systemName: sourceTab == 0 ? "arrow.right" : "arrow.down.right.and.arrow.up.left") }
                Text(sourceTab == 0 ? L("Continuer avec cette vidéo") : busy ? L("Compression en cours…") : L("Compresser la vidéo"))
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selected ? Color.brand : Color.gray.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!selected || busy)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var photosGrid: some View {
        switch photosAuthorization {
        case .authorized, .limited:
            if photoVideos.isEmpty {
                EmptyState(icon: "film", title: L("Aucune vidéo à compresser"), subtitle: L("Votre photothèque ne contient pas de vidéo."))
                    .frame(maxWidth: .infinity).padding(.vertical, 48)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 12) {
                    ForEach(photoVideos, id: \.localIdentifier) { asset in
                        let isSelected = chosenPhoto?.localIdentifier == asset.localIdentifier
                        Button { chosenPhoto = asset } label: { PhotoVideoCard(asset: asset, isSelected: isSelected) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        case .notDetermined:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
        default:
            VStack(spacing: 12) {
                Label(L("Accès aux Photos refusé"), systemImage: "lock.circle")
                Text(L("Autorisez Faxel à accéder à vos photos dans les Réglages pour compresser vos vidéos."))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("Ouvrir les Réglages")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 36)
        }
    }

    private func loadPhotos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { updated in
                DispatchQueue.main.async { photosAuthorization = updated; if updated == .authorized || updated == .limited { loadPhotos() } }
            }
            return
        }
        photosAuthorization = status
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        photoVideos = assets
    }

    private func videoCard(_ track: Track) -> some View {
        let selected = selectedPath == track.path
        return Button { selectedPath = track.path } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Artwork(url: track.thumbnail, seed: track.id, icon: "play.rectangle.fill",
                            width: 180, height: 104, radius: 12)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white, Color.brand)
                            .padding(6)
                            .accessibilityLabel(L("Vidéo sélectionnée"))
                    }
                    if model.compressing.contains(track.path) {
                        ProgressView().padding(7).background(.ultraThinMaterial, in: Circle()).padding(6)
                    }
                }
                Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(Fmt.size(fileSize(track.path))).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.brand : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PhotoAssetSelection: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// Extrait toute la piste sonore ou un passage choisi d'une vidéo locale.
struct VideoAudioConversionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var trim = false
    @State private var duration = 1.0
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var exporting = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var currentExport: AVAssetExportSession?

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Vidéo source")) {
                    Text(track.title).font(.headline)
                    Text(L("Le son sera enregistré en M4A (AAC, audio MP4), à côté de la vidéo."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L("Extrait")) {
                    Toggle(L("Couper un extrait"), isOn: $trim)
                    if trim {
                        Text(L("Début : {time}", ["time": Fmt.clock(start)]))
                        Slider(value: $start, in: 0...max(0.1, duration - 0.1))
                            .onChange(of: start) { value in if end <= value { end = min(duration, value + 0.1) } }
                        Text(L("Fin : {time}", ["time": Fmt.clock(end)]))
                        Slider(value: $end, in: min(duration, start + 0.1)...max(duration, start + 0.1))
                    }
                    if exporting {
                        ProgressView(value: progress)
                        Button(L("Annuler"), role: .destructive) { currentExport?.cancelExport() }
                    } else {
                        Button { convert() } label: { Label(L("Convertir en audio"), systemImage: "waveform") }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(L("Vidéo vers audio"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(exporting ? L("Annuler") : L("Fermer")) {
                    if exporting { currentExport?.cancelExport() } else { dismiss() }
                }
            } }
            .interactiveDismissDisabled(exporting)
        }
        .onAppear {
            duration = max(MediaLibrary.shared.duration(track) ?? 1, 1)
            end = duration
        }
    }

    private func convert() {
        let source = track.fileURL
        let base = source.deletingLastPathComponent().appendingPathComponent(source.deletingPathExtension().lastPathComponent + " (audio)")
        var target = base.appendingPathExtension("m4a")
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = URL(fileURLWithPath: base.path + " \(suffix).m4a")
            suffix += 1
        }
        exporting = true
        progress = 0
        error = nil
        MediaCompressor.extractAudio(source: source, target: target, start: trim ? start : 0, end: trim ? end : nil,
                                     progress: { progress = $0 }, exportSession: { currentExport = $0 }) { result in
            exporting = false
            currentExport = nil
            switch result {
            case .success:
                model.rescan(force: true) {
                    model.show(L("Audio créé : {name}", ["name": target.lastPathComponent]), .ok)
                    dismiss()
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }
}

private struct PhotoVideoCard: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottom) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { Color.secondary.opacity(0.2) }
                }
                .frame(height: 126).frame(maxWidth: .infinity).clipped()
                HStack {
                    Text(Fmt.clock(asset.duration))
                    Spacer()
                    Text(Fmt.size(photoAssetSize(asset)))
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                .padding(5).background(.black.opacity(0.65))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.brand)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                }
            }
            Text(photoAssetName(asset)).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color.brand : .clear, lineWidth: 2))
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 360, height: 280), contentMode: .aspectFill, options: options) { result, _ in
                DispatchQueue.main.async { image = result }
            }
        }
    }
}

private func photoAssetName(_ asset: PHAsset) -> String {
    PHAssetResource.assetResources(for: asset).first?.originalFilename ?? L("Vidéo")
}

private func photoAssetSize(_ asset: PHAsset) -> Double {
    let resource = PHAssetResource.assetResources(for: asset).first { $0.type == .video || $0.type == .fullSizeVideo }
    return (resource?.value(forKey: "fileSize") as? NSNumber)?.doubleValue ?? 0
}

private struct PhotoCompressionSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var preset = AVAssetExportPreset1280x720
    @State private var exporting = false
    @State private var progress: Double = 0
    @State private var output: URL?
    @State private var outputSize: Double = 0
    @State private var error: String?
    @State private var saved = false
    @State private var currentExport: AVAssetExportSession?
    private let presets = [("1080p", AVAssetExportPreset1920x1080), ("720p", AVAssetExportPreset1280x720), ("540p", AVAssetExportPreset960x540), ("480p", AVAssetExportPreset640x480)]

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Vidéo")) {
                    LabeledContent(L("Nom"), value: photoAssetName(asset))
                    LabeledContent(L("Taille actuelle"), value: Fmt.size(photoAssetSize(asset)))
                }
                if let output {
                    Section(L("Résultat")) {
                        LabeledContent(L("Nouvelle taille"), value: Fmt.size(outputSize))
                        Button(L("Enregistrer dans Photos")) {
                            PhotoSaver.save(video: output, images: []) { ok, message in saved = ok; if !ok { error = message } }
                        }
                        .disabled(saved)
                        if saved { Label(L("Enregistrée dans Photos."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                } else {
                    Section {
                        Picker(L("Qualité"), selection: $preset) {
                            ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
                        }
                        if exporting {
                            ProgressView(value: progress)
                            Button(L("Annuler"), role: .destructive) { currentExport?.cancelExport() }
                        } else {
                            Button { Task { await compress() } } label: { Label(L("Compresser"), systemImage: "rectangle.compress.vertical") }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(L("Compression"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(exporting ? L("Annuler") : L("Fermer")) {
                    if exporting { currentExport?.cancelExport() } else { dismiss() }
                }
            } }
            .interactiveDismissDisabled(exporting)
        }
    }

    @MainActor private func compress() async {
        exporting = true; error = nil; progress = 0
        let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = true; options.version = .current
        let asset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: self.asset, options: options) { avAsset, _, _ in continuation.resume(returning: avAsset) }
        }
        guard let asset, let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            exporting = false; error = L("Cette vidéo ne peut pas être compressée."); return
        }
        let outputType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        guard session.supportedFileTypes.contains(outputType) else {
            exporting = false
            error = L("Le format de compression n'est pas compatible avec cette vidéo.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (outputType == .mp4 ? ".mp4" : ".mov"))
        session.outputURL = url; session.outputFileType = outputType; session.shouldOptimizeForNetworkUse = true
        currentExport = session
        let progressTask = Task { @MainActor in
            while session.status == .exporting {
                progress = Double(session.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        progressTask.cancel()
        progress = session.status == .completed ? 1 : progress
        exporting = false
        currentExport = nil
        if session.status == .completed {
            output = url
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            outputSize = (attributes?[.size] as? NSNumber)?.doubleValue ?? 0
        } else if session.status != .cancelled {
            try? FileManager.default.removeItem(at: url)
            error = session.error?.localizedDescription ?? L("La compression a échoué.")
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
