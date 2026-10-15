import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Ouvre l'outil « Retirer un filigrane » depuis la bibliothèque (menu d'une vidéo).
final class WatermarkCenter: ObservableObject {
    static let shared = WatermarkCenter()
    @Published var track: Track?
}

struct WatermarkPresenter: ViewModifier {
    @ObservedObject private var center = WatermarkCenter.shared
    let model: AppModel

    func body(content: Content) -> some View {
        content.sheet(item: $center.track) { track in
            WatermarkView(track: track)
                .environmentObject(model)
        }
    }
}

extension View {
    func watermarkEditor(_ model: AppModel) -> some View { modifier(WatermarkPresenter(model: model)) }
}

/// Une zone à flouter, en proportions de l'image (0…1, origine en haut à gauche).
struct WatermarkZone: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
}

/// Crée une copie de la vidéo où les zones choisies (logo, filigrane, texte) sont floutées
/// ou pixellisées sur toute la durée. L'original n'est pas modifié.
final class WatermarkExporter: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var result: URL?
    @Published private(set) var failed: String?

    private var session: AVAssetExportSession?
    private var timer: Timer?

    func export(source: URL, zones: [CGRect], pixelate: Bool, strength: Double) {
        guard !running, !zones.isEmpty else { return }
        running = true
        progress = 0
        result = nil
        failed = nil
        let asset = AVURLAsset(url: source)
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let image = request.sourceImage
            let extent = image.extent
            var output = image
            for zone in zones {
                let area = CGRect(
                    x: extent.minX + zone.minX * extent.width,
                    y: extent.minY + (1 - zone.maxY) * extent.height,
                    width: zone.width * extent.width,
                    height: zone.height * extent.height
                ).integral.intersection(extent)
                guard area.width > 2, area.height > 2 else { continue }
                let patch: CIImage?
                if pixelate {
                    let filter = CIFilter.pixellate()
                    filter.inputImage = image.clampedToExtent()
                    filter.center = CGPoint(x: area.midX, y: area.midY)
                    let side = Double(max(extent.width, extent.height))
                    let scale: Double = max(6, (4 + strength * 26) * side / 720)
                    filter.scale = Float(scale)
                    patch = filter.outputImage
                } else {
                    let filter = CIFilter.gaussianBlur()
                    filter.inputImage = image.clampedToExtent()
                    let side = Double(max(extent.width, extent.height))
                    let radius: Double = (6 + strength * 34) * side / 720
                    filter.radius = Float(radius)
                    patch = filter.outputImage
                }
                if let patch = patch {
                    output = patch.cropped(to: area).composited(over: output)
                }
            }
            request.finish(with: output.cropped(to: extent), context: nil)
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            running = false
            failed = L("Export impossible pour cette vidéo.")
            return
        }
        let target = WatermarkExporter.targetURL(for: source)
        export.outputURL = target
        export.outputFileType = export.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        export.videoComposition = composition
        export.shouldOptimizeForNetworkUse = true
        session = export
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, let session = self.session else { return }
            self.progress = Double(session.progress)
        }
        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.timer?.invalidate()
                self.timer = nil
                self.running = false
                switch export.status {
                case .completed:
                    self.progress = 1
                    self.result = target
                case .cancelled:
                    try? FileManager.default.removeItem(at: target)
                default:
                    try? FileManager.default.removeItem(at: target)
                    self.failed = export.error?.localizedDescription ?? L("Export impossible pour cette vidéo.")
                }
                self.session = nil
            }
        }
    }

    func cancel() {
        session?.cancelExport()
    }

    /// « Ma vidéo (sans filigrane).mp4 » à côté de l'original (sans écraser un fichier existant).
    static func targetURL(for source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + " (" + L("sans filigrane") + ")"
        var candidate = folder.appendingPathComponent(base + ".mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(base + " \(n).mp4")
            n += 1
        }
        return candidate
    }
}

struct WatermarkView: View {
    let track: Track
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exporter = WatermarkExporter()

    @State private var frame: UIImage?
    @State private var duration: Double = 0
    @State private var time: Double = 0
    @State private var zones: [WatermarkZone] = []
    @State private var drawing: CGRect?
    @State private var pixelate = false
    @State private var strength: Double = 0.5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Dessinez un rectangle sur le logo ou le texte à cacher. Vous pouvez ajouter plusieurs zones (le logo TikTok change de coin pendant la vidéo)."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    preview
                    if duration > 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            Slider(value: $time, in: 0...duration, onEditingChanged: { editing in
                                if !editing { loadFrame() }
                            })
                            Text(L("Image à {time} (déplacez pour voir où est le logo)", ["time": Fmt.clock(time)]))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    presets
                    Picker("", selection: $pixelate) {
                        Text(L("Flou")).tag(false)
                        Text(L("Pixels")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Intensité")).font(.subheadline.weight(.semibold))
                        Slider(value: $strength, in: 0...1)
                    }
                    exportSection
                }
                .padding()
            }
            .navigationTitle(L("Retirer un filigrane"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Fermer")) {
                        exporter.cancel()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: exporter.result) { result in
            if result != nil { model.rescan(force: true) }
        }
        .onAppear {
            let asset = AVURLAsset(url: track.fileURL)
            duration = max(0, asset.duration.seconds.isFinite ? asset.duration.seconds : (track.duration ?? 0))
            time = min(1, duration)
            loadFrame()
        }
    }

    // MARK: - Aperçu et zones

    private var preview: some View {
        let ratio = frame.map { $0.size.width / max($0.size.height, 1) } ?? 16 / 9
        return GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let frame = frame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Color.black
                    ProgressView().frame(width: size.width, height: size.height)
                }
                ForEach(zones) { zone in
                    zoneView(zone.rect, size: size, color: .brand)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                zones.removeAll { $0.id == zone.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, .red)
                            }
                            .offset(x: 10, y: -10)
                        }
                        .offset(x: zone.rect.minX * size.width, y: zone.rect.minY * size.height)
                }
                if let drawing = drawing {
                    zoneView(drawing, size: size, color: .yellow)
                        .offset(x: drawing.minX * size.width, y: drawing.minY * size.height)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        drawing = normalized(value.startLocation, value.location, size: size)
                    }
                    .onEnded { value in
                        let rect = normalized(value.startLocation, value.location, size: size)
                        drawing = nil
                        if rect.width > 0.02, rect.height > 0.02, zones.count < 6 {
                            zones.append(WatermarkZone(rect: rect))
                        }
                    }
            )
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func zoneView(_ rect: CGRect, size: CGSize, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(color, lineWidth: 2))
            .frame(width: rect.width * size.width, height: rect.height * size.height)
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint, size: CGSize) -> CGRect {
        let x0 = min(max(0, min(a.x, b.x) / max(size.width, 1)), 1)
        let y0 = min(max(0, min(a.y, b.y) / max(size.height, 1)), 1)
        let x1 = min(max(0, max(a.x, b.x) / max(size.width, 1)), 1)
        let y1 = min(max(0, max(a.y, b.y) / max(size.height, 1)), 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetButton(L("TikTok (2 coins)")) {
                    zones.append(WatermarkZone(rect: CGRect(x: 0.03, y: 0.04, width: 0.42, height: 0.11)))
                    zones.append(WatermarkZone(rect: CGRect(x: 0.55, y: 0.83, width: 0.42, height: 0.11)))
                }
                presetButton(L("Haut gauche")) { zones.append(WatermarkZone(rect: CGRect(x: 0.02, y: 0.03, width: 0.3, height: 0.12))) }
                presetButton(L("Haut droit")) { zones.append(WatermarkZone(rect: CGRect(x: 0.68, y: 0.03, width: 0.3, height: 0.12))) }
                presetButton(L("Bas gauche")) { zones.append(WatermarkZone(rect: CGRect(x: 0.02, y: 0.85, width: 0.3, height: 0.12))) }
                presetButton(L("Bas droit")) { zones.append(WatermarkZone(rect: CGRect(x: 0.68, y: 0.85, width: 0.3, height: 0.12))) }
                if !zones.isEmpty {
                    presetButton(L("Tout effacer")) { zones.removeAll() }
                }
            }
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        if exporter.running {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Création de la copie… {percent} %", ["percent": "\(Int(exporter.progress * 100))"]))
                ProgressView(value: exporter.progress)
                Button(L("Annuler"), role: .destructive) { exporter.cancel() }
            }
        } else if let result = exporter.result {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Copie créée : {name}", ["name": result.lastPathComponent]), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                ShareLink(item: result) {
                    Label(L("Partager"), systemImage: "square.and.arrow.up")
                }
                Button(L("Terminé")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let failed = exporter.failed {
                    Label(failed, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                }
                Button {
                    exporter.export(source: track.fileURL, zones: zones.map { $0.rect }, pixelate: pixelate, strength: strength)
                } label: {
                    Label(L("Créer la copie sans filigrane"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(zones.isEmpty)
                Text(L("L'original est conservé. La copie apparaît dans la bibliothèque, à côté de la vidéo."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadFrame() {
        let url = track.fileURL
        let at = time
        DispatchQueue.global(qos: .userInitiated).async {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            let image = try? generator.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: nil)
            DispatchQueue.main.async {
                if let image = image { frame = UIImage(cgImage: image) }
            }
        }
    }
}
