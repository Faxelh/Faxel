import SwiftUI
import UIKit

/// Onglet Rechercher : dans votre bibliothèque (morceaux, artistes, albums,
/// vidéos) ou sur YouTube, avec téléchargement en un geste.
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @AppStorage("searchQuery") private var query = ""
    @State private var picking: Track?
    @State private var deleting: Track?
    @State private var quick: QuickLink?

    private var text: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack(path: $model.searchPath) {
            List {
                if text.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: L("Cherchez un titre, un artiste, une vidéo"),
                               subtitle: L("Les résultats de votre bibliothèque s'affichent en tapant ; touchez « Rechercher » pour YouTube, puis « Télécharger »."))
                        .listRowSeparator(.hidden)
                } else {
                    libraryResults
                    onlineSection
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("Rechercher"))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Titre, artiste, vidéo…"))
            .onSubmit(of: .search) {
                model.searchOnline(query)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { model.showSearch = false }
                }
            }
            .libraryDestinations()
            .trackSheets(picking: $picking, deleting: $deleting)
            .coverEditor()
            .sheet(item: $quick) { link in
                QuickDownloadSheet(link: link)
                    .environmentObject(model)
            }
        }
    }

    // MARK: - YouTube

    @ViewBuilder
    private var onlineSection: some View {
        Section(header: header("YouTube")) {
            if model.searchingOnline {
                HStack {
                    Spacer()
                    ProgressView(L("Recherche…"))
                    Spacer()
                }
                .padding(.vertical, 20)
                .listRowSeparator(.hidden)
            } else if model.onlineQuery.lowercased() == text && !model.onlineResults.isEmpty {
                ForEach(model.onlineResults) { result in
                    OnlineResultRow(result: result) {
                        quick = QuickLink(url: result.url, title: result.title, thumbnail: result.thumbnail)
                    }
                }
            } else {
                Button {
                    model.searchOnline(query)
                } label: {
                    Label(L("Chercher « {query} » sur YouTube", ["query": query]), systemImage: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.brand)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Bibliothèque

    @ViewBuilder
    private var libraryResults: some View {
        if !text.isEmpty {
            let songs = model.songs.filter { matches($0) }
            let videos = model.videos.filter { matches($0) }
            let artists = library.artists(model.songs).filter { $0.name.lowercased().contains(text) }
            let albums = library.albums(model.songs).filter {
                $0.name.lowercased().contains(text) || $0.subtitle.lowercased().contains(text)
            }
            if !artists.isEmpty {
                Section(header: header(L("Artistes"))) {
                    ForEach(artists.prefix(6)) { artist in
                        NavigationLink(value: LibraryRoute.artist(artist.id)) {
                            HStack(spacing: 12) {
                                Artwork(url: artist.artwork, seed: artist.id, icon: "music.mic", width: 46, height: 46, radius: 23)
                                Text(artist.name)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                    }
                }
            }
            if !albums.isEmpty {
                Section(header: header(L("Albums"))) {
                    ForEach(albums.prefix(6)) { album in
                        NavigationLink(value: LibraryRoute.album(album.id)) {
                            HStack(spacing: 12) {
                                Artwork(url: album.artwork, seed: album.id, icon: "square.stack.fill", width: 46, height: 46, radius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name)
                                        .font(.system(size: 16, weight: .medium))
                                    Text(album.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !songs.isEmpty {
                Section(header: header(L("Morceaux"))) {
                    ForEach(Array(songs.prefix(40).enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, onTap: { model.play(Array(songs.prefix(40)), start: index) }) {
                            TrackActions(track: track, picking: $picking, deleting: $deleting)
                        }
                    }
                }
            }
            if !videos.isEmpty {
                Section(header: header(L("Vidéos"))) {
                    ForEach(Array(videos.prefix(30).enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, onTap: { model.play(Array(videos.prefix(30)), start: index) }) {
                            TrackActions(track: track, picking: $picking, deleting: $deleting)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ track: Track) -> Bool {
        library.title(track).lowercased().contains(text)
            || library.artist(track).lowercased().contains(text)
            || (library.album(track)?.lowercased().contains(text) ?? false)
            || track.platformName.lowercased().contains(text)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.primary)
            .textCase(nil)
    }
}

/// Résultat YouTube : « Télécharger » ouvre le choix Vidéo / Audio et qualité.
struct OnlineResultRow: View {
    @EnvironmentObject var model: AppModel
    let result: WebResult
    let download: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: result.thumbnail, seed: result.url, icon: "play.rectangle.fill", width: 104, height: 58, radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(result.meta)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Button(action: download) {
                    Label(L("Télécharger"), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.brand))
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: download)
        .contextMenu {
            Button {
                model.quickDownload([["url": result.url, "title": result.title]], media: "audio", quality: "Meilleure")
            } label: {
                Label(L("Télécharger l'audio"), systemImage: "music.note")
            }
            Button {
                model.quickDownload([["url": result.url, "title": result.title]], media: "video", quality: model.quality)
            } label: {
                Label(L("Télécharger la vidéo"), systemImage: "film")
            }
            Button {
                UIPasteboard.general.string = result.url
                model.show(L("Lien copié."), .ok)
            } label: {
                Label(L("Copier le lien"), systemImage: "link")
            }
        }
    }
}
