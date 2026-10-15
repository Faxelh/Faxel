import SwiftUI
import UIKit

/// Un lien à télécharger tout de suite (navigateur, recherche YouTube).
struct QuickLink: Identifiable {
    let id = UUID()
    let url: String
    var title = ""
    var thumbnail: String?
}

/// Feuille « Télécharger » : analyse du lien, choix Vidéo / Audio et qualité,
/// puis ajout à la file, sans quitter l'écran en cours.
struct QuickDownloadSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let link: QuickLink

    @State private var analysis: Analysis?
    @State private var loading = true
    @State private var message: String?
    @State private var media = UserDefaults.standard.string(forKey: "defaultMedia") ?? "video"
    @State private var quality = UserDefaults.standard.string(forKey: "defaultQuality") ?? "Meilleure"
    @State private var added = false
    @State private var playlistLoading = false

    private var qualities: [String] {
        guard let analysis = analysis, analysis.kind != "photo", !analysis.qualities.isEmpty else {
            return analysis?.kind == "photo" ? ["Meilleure"] : standardQualities
        }
        return analysis.qualities
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L("Analyse en cours…")).foregroundColor(.secondary)
                        }
                    } else if let message = message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Format").uppercased())
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Picker("", selection: $media) {
                            Text(L("Vidéo")).tag("video")
                            Text(L("Audio (musique)")).tag("audio")
                        }
                        .pickerStyle(.segmented)
                    }

                    if media == "video" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Qualité").uppercased())
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(qualities, id: \.self) { item in
                                        Button {
                                            quality = item
                                        } label: {
                                            Text(qualityLabel(item))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(quality == item ? .white : .primary)
                                                .padding(.horizontal, 16)
                                                .frame(height: 36)
                                                .background(Capsule().fill(quality == item ? Color.brand
                                                                           : Color(.tertiarySystemFill)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Button(action: start) {
                        Label(added ? L("Ajouté aux téléchargements") : startTitle,
                              systemImage: added ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(added)

                    if let info = analysis, !info.playlistURL.isEmpty {
                        Button {
                            playlistLoading = true
                            model.downloadPlaylist(info.playlistURL, media: media, quality: quality) { ok in
                                playlistLoading = false
                                if ok {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    withAnimation { added = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if playlistLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "list.bullet.rectangle")
                                }
                                Text(playlistLoading ? L("Lecture de la playlist…") : L("Télécharger toute la playlist"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .disabled(added || playlistLoading)
                        Text(L("Seule la vidéo affichée est téléchargée, sauf si vous choisissez toute la playlist."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    if let info = analysis, info.kind == "playlist", !info.entries.isEmpty {
                        Button {
                            enqueue(info.entries.map { ["url": $0.url, "title": $0.title] })
                        } label: {
                            Text(L("Tout télécharger ({count})", ["count": "\(info.entries.count)"]))
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .disabled(added)
                    }
                }
                .padding(20)
            }
            .navigationTitle(L("Télécharger"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: analyze)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Artwork(url: analysis?.thumbnail ?? link.thumbnail, seed: link.url,
                    icon: analysis?.kind == "photo" ? "photo.on.rectangle.angled" : "play.rectangle.fill",
                    width: 112, height: 70, radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(analysis?.title.isEmpty == false ? (analysis?.title ?? "") : (link.title.isEmpty ? link.url : link.title))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                if let details = analysis?.details, !details.isEmpty {
                    Text(details)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var startTitle: String {
        if analysis?.kind == "playlist" { return L("Télécharger la 1re vidéo") }
        return media == "audio" ? L("Télécharger l'audio") : L("Télécharger la vidéo")
    }

    private func analyze() {
        // Analyse trop longue (page sans vidéo, réseau lent) : on n'attend pas indéfiniment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if loading {
                loading = false
                message = L("L'analyse prend trop de temps. Vous pouvez quand même lancer le téléchargement.")
            }
        }
        model.analyze(link.url) { info, error in
            guard loading || analysis == nil else { return }
            loading = false
            analysis = info
            message = error
            guard let info = info else { return }
            if !info.videoOK && info.audioOK { media = "audio" }
            if !qualities.contains(quality) {
                quality = qualities.first ?? "Meilleure"
            }
        }
    }

    private func start() {
        if let info = analysis {
            if info.kind == "playlist", let first = info.entries.first {
                enqueue([["url": first.url, "title": first.title]])
            } else {
                enqueue([["url": info.url.isEmpty ? link.url : info.url, "title": info.title]])
            }
        } else {
            enqueue([["url": link.url, "title": link.title]])
        }
    }

    private func enqueue(_ items: [[String: Any]]) {
        model.quickDownload(items, media: media, quality: media == "audio" ? "Meilleure" : quality)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { added = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}
