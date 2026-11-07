import SwiftUI

/// Accès direct au compresseur depuis l'accueil, avec l'original gardé intact.
struct CompressionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L("Choisissez une vidéo. Faxel crée une copie compressée dans la bibliothèque et conserve le fichier original."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if model.videos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text(L("Aucune vidéo à compresser")).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .listRowBackground(Color.clear)
                } else {
                    Section(L("Vidéos")) {
                        ForEach(model.videos) { track in
                            Button { model.compress(track) } label: {
                                HStack(spacing: 12) {
                                    Artwork(url: track.thumbnail, seed: track.id, icon: "play.rectangle.fill",
                                            width: 72, height: 48, radius: 8)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                        Text(Fmt.size(fileSize(track.path)))
                                            .font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    if model.compressing.contains(track.path) {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                            .foregroundStyle(Color.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.compressing.contains(track.path))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
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
}
