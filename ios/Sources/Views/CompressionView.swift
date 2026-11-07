import AVFoundation
import SwiftUI

/// Sélectionne une vidéo, sa qualité cible puis démarre une copie compressée.
struct CompressionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath = ""
    @State private var selectedPreset = AVAssetExportPreset1280x720

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
                            Button {
                                model.compress(track, videoPreset: selectedPreset)
                            } label: {
                                HStack(spacing: 8) {
                                    if model.compressing.contains(track.path) { ProgressView(value: model.compressionProgress[track.path] ?? 0).tint(Color.brand) }
                                    else { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                                    Text(model.compressing.contains(track.path) ? L("Compression en cours…") : L("Compresser la vidéo"))
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(model.compressing.contains(track.path))
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
        }
        .presentationDetents([.medium, .large])
    }

    private func videoCard(_ track: Track) -> some View {
        let selected = selectedPath == track.path
        return Button { selectedPath = track.path } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Artwork(url: track.thumbnail, seed: track.id, icon: "play.rectangle.fill",
                            width: 180, height: 104, radius: 12)
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
