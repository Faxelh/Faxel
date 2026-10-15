import AVFoundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Onglet Bibliothèque, comme dans Musique : Playlists, Artistes, Albums,
/// Morceaux, Vidéos, Téléchargés, Favoris, Fichiers, Coffre.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @ObservedObject private var virtualFolders = VirtualFolderStore.shared
    @State private var importing = false
    @State private var creating = false
    @State private var newName = ""
    @State private var showWifi = false

    var body: some View {
        NavigationStack(path: $model.libraryPath) {
            List {
                if let error = model.engineError {
                    Section {
                        EngineErrorCard(message: error)
                    }
                }
                Section {
                    row(.playlists, L("Playlists"), "music.note.list", count: model.playlists.count + 1)
                    row(.artists, L("Artistes"), "music.mic", count: nil)
                    row(.albums, L("Albums"), "square.stack.fill", count: nil)
                    row(.songs, L("Morceaux"), "music.note", count: model.songs.count)
                    row(.videos, L("Vidéos"), "film.fill", count: model.videos.count)
                    row(.virtualFolders, L("Dossiers virtuels"), "folder.fill.badge.gearshape",
                        count: virtualFolders.folders.count)
                    row(.downloads, L("Téléchargés"), "arrow.down.circle.fill", count: model.downloads.count)
                    row(.favorites, L("Favoris"), "heart.fill", count: model.favoriteTracks.count)
                    row(.files(PythonEngine.documentsURL.path), L("Fichiers"), "folder.fill", count: nil)
                    Button {
                        model.openVault()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 19))
                                .foregroundColor(.red)
                                .frame(width: 28)
                            Text(L("Coffre"))
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                }

                let recent = Array(model.recentlyAdded.prefix(12))
                Section {
                    if recent.isEmpty {
                        if model.libraryLoaded || model.engineError != nil {
                            AddMusicCard(importing: $importing)
                                .listRowSeparator(.hidden)
                        } else {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 30)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    model.play(recent, start: index)
                                } label: {
                                    RecentTile(track: track)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(L("Ajoutés récemment"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("Bibliothèque"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            importing = true
                        } label: {
                            Label(L("Importer depuis Fichiers"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showWifi = true
                        } label: {
                            Label(L("Transfert Wi-Fi depuis l'ordinateur"), systemImage: "wifi")
                        }
                        Button {
                            newName = ""
                            creating = true
                        } label: {
                            Label(L("Nouvelle playlist"), systemImage: "music.note.list")
                        }
                        Button {
                            model.rescan(force: true)
                        } label: {
                            Label(L("Actualiser la bibliothèque"), systemImage: "arrow.clockwise")
                        }
                        Button {
                            model.openInFiles()
                        } label: {
                            Label(L("Ouvrir dans Fichiers"), systemImage: "folder")
                        }
                    } label: {
                        CircleIcon(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await MainActor.run { model.rescan(force: true) }
            }
            .libraryDestinations()
            .importer(isPresented: $importing)
            .sheet(isPresented: $showWifi) {
                WifiTransferView()
                    .environmentObject(model)
            }
            .alert(L("Nouvelle playlist"), isPresented: $creating) {
                TextField(L("Nom de la playlist"), text: $newName)
                Button(L("Annuler"), role: .cancel) {}
                Button(L("Créer")) {
                    model.createPlaylist(newName) { uid in
                        model.libraryPath = [.playlist(uid)]
                    }
                }
            }
        }
    }

    private func row(_ route: LibraryRoute, _ title: String, _ icon: String, count: Int?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundColor(.brand)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 18))
                Spacer()
                if let count = count, count > 0 {
                    Text("\(count)")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

/// Vignette « Ajoutés récemment » (pochette carrée, ou image de la vidéo).
struct RecentTile: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    TrackArtwork(track: track, width: geometry.size.width, height: geometry.size.width, radius: 10)
                    if track.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .padding(6)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(library.title(track))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(track.isAudio ? library.artist(track) : (track.platformName.isEmpty ? L("Vidéo") : track.platformName))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

/// Bibliothèque vide : comment ajouter de la musique et des vidéos.
struct AddMusicCard: View {
    @EnvironmentObject var model: AppModel
    @Binding var importing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Ajoutez votre musique et vos vidéos"), systemImage: "music.note.house.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.brand)
            tip("desktopcomputer", L("Avec 3uTools (ou iTunes / Finder) : Apps › Faxel › Documents, glissez vos fichiers. Ils apparaissent ici automatiquement."))
            tip("folder", L("Avec l'app Fichiers : copiez-les dans « Sur mon iPhone › Faxel », ou touchez « Importer »."))
            tip("arrow.down.circle", L("Ou téléchargez depuis YouTube, TikTok, Instagram, Facebook… dans l'onglet Télécharger."))
            HStack(spacing: 10) {
                Button {
                    importing = true
                } label: {
                    Label(L("Importer"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    model.tab = .download
                } label: {
                    Label(L("Télécharger"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.brand.opacity(0.1)))
        .padding(.vertical, 6)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.brand)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Navigation commune (Accueil, Bibliothèque, Recherche)

struct LibraryDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .playlists:
                PlaylistsListView()
            case .artists:
                ArtistsView()
            case .albums:
                AlbumsView()
            case .songs:
                SongsView()
            case .videos:
                VideosView()
            case .downloads:
                DownloadsListView()
            case .files(let path):
                FilesView(path: path)
            case .artist(let id):
                ArtistDetailView(id: id)
            case .album(let id):
                AlbumDetailView(id: id)
            case .virtualFolders:
                VirtualFoldersView()
            case .virtualFolder(let id):
                VirtualFolderView(id: id)
            case .favorites, .vault, .playlist:
                CollectionView(route: route)
            }
        }
    }
}

/// Import de sons et vidéos depuis l'app Fichiers.
struct ImporterModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.audio, .movie, .data, .folder],
                             allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importFiles(urls)
            case .failure:
                model.show(L("Import impossible."), .error)
            }
        }
    }
}

extension View {
    func libraryDestinations() -> some View {
        modifier(LibraryDestinations())
    }

    func importer(isPresented: Binding<Bool>) -> some View {
        modifier(ImporterModifier(isPresented: isPresented))
    }
}

// MARK: - Playlists

struct PlaylistsListView: View {
    @EnvironmentObject var model: AppModel
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            Button {
                newName = ""
                creating = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.brand)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                    Text(L("Nouvelle playlist…"))
                        .foregroundColor(.brand)
                }
            }
            NavigationLink(value: LibraryRoute.favorites) {
                playlistRow(L("Favoris"), detail: L("{count} élément(s)", ["count": "\(model.favoriteTracks.count)"]),
                            artwork: model.favoriteTracks.lazy.compactMap { MediaLibrary.shared.artwork($0) }.first,
                            seed: "favoris", icon: "heart.fill")
            }
            ForEach(model.playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                    playlistRow(playlist.name, detail: L("{count} élément(s)", ["count": "\(playlist.items.count)"]),
                                artwork: playlist.items.lazy.compactMap { MediaLibrary.shared.artwork($0) }.first,
                                seed: playlist.id, icon: "music.note.list")
                }
                .swipeActions {
                    Button(role: .destructive) {
                        model.deletePlaylist(playlist)
                    } label: {
                        Label(L("Supprimer"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Playlists"))
        .alert(L("Nouvelle playlist"), isPresented: $creating) {
            TextField(L("Nom de la playlist"), text: $newName)
            Button(L("Annuler"), role: .cancel) {}
            Button(L("Créer")) { model.createPlaylist(newName) }
        }
    }

    private func playlistRow(_ title: String, detail: String, artwork: String?, seed: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Artwork(url: artwork, seed: seed, icon: icon, width: 56, height: 56, radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Morceaux

struct SongsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @AppStorage("songsSort") private var sort = "title"
    @State private var query = ""
    @State private var picking: Track?
    @State private var deleting: Track?

    private var songs: [Track] {
        var list = model.songs
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !text.isEmpty {
            list = list.filter {
                library.title($0).lowercased().contains(text) || library.artist($0).lowercased().contains(text)
                    || (library.album($0)?.lowercased().contains(text) ?? false)
            }
        }
        switch sort {
        case "artist":
            return list.sorted {
                let left = library.artist($0)
                let right = library.artist($1)
                if left != right { return left.localizedCaseInsensitiveCompare(right) == .orderedAscending }
                return library.title($0).localizedCaseInsensitiveCompare(library.title($1)) == .orderedAscending
            }
        case "recent":
            return list.sorted { $0.addedDate > $1.addedDate }
        default:
            return library.sortByTitle(list)
        }
    }

    var body: some View {
        let list = songs
        List {
            if list.isEmpty {
                EmptyState(icon: "music.note", title: query.isEmpty ? L("Aucun morceau") : L("Aucun résultat"),
                           subtitle: query.isEmpty ? L("Ajoutez des sons avec 3uTools, l'app Fichiers, ou téléchargez-les.") : "")
                    .listRowSeparator(.hidden)
            } else {
                PlayShuffleButtons(tracks: list)
                    .listRowSeparator(.hidden)
                ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, onTap: { model.play(list, start: index) }) {
                        TrackActions(track: track, picking: $picking, deleting: $deleting)
                    }
                    .contextMenu {
                        TrackActions(track: track, picking: $picking, deleting: $deleting)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            model.playNext(track)
                        } label: {
                            Label(L("Lire ensuite"), systemImage: "text.insert")
                        }
                        .tint(.brand)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleting = track
                        } label: {
                            Label(L("Supprimer"), systemImage: "trash")
                        }
                        Button {
                            model.toggleFavorite(track)
                        } label: {
                            Label(L("Favori"), systemImage: model.isFavorite(track) ? "heart.slash" : "heart")
                        }
                        .tint(.pink)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Morceaux"))
        .searchable(text: $query, prompt: L("Rechercher dans les morceaux"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker(L("Trier par"), selection: $sort) {
                        Text(L("Titre")).tag("title")
                        Text(L("Artiste")).tag("artist")
                        Text(L("Ajout récent")).tag("recent")
                    }
                } label: {
                    CircleIcon(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .trackSheets(picking: $picking, deleting: $deleting)
    }
}

// MARK: - Vidéos

struct VideosView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @AppStorage("videosGrid") private var grid = true
    @AppStorage("videosFolder") private var folder = ""
    @State private var query = ""
    @State private var picking: Track?
    @State private var deleting: Track?

    private var allVideos: [Track] {
        model.videos.sorted { $0.addedDate > $1.addedDate }
    }

    /// Les vidéos rangées par dossier (Facebook, TikTok, YouTube, Importés › …).
    private func folders(_ all: [Track]) -> [VideoFolder] {
        var groups: [String: [Track]] = [:]
        var order: [String] = []
        for track in all {
            let name = VideoFolder.name(of: track)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(track)
        }
        return order.map { VideoFolder(name: $0, items: groups[$0] ?? []) }
            .sorted { $0.items.count > $1.items.count }
    }

    private func filtered(_ all: [Track]) -> [Track] {
        var list = all
        if !folder.isEmpty {
            list = list.filter { VideoFolder.name(of: $0) == folder }
            list = VideoFolder.episodeOrder(list)
        }
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return list }
        return list.filter { library.title($0).lowercased().contains(text) || $0.platformName.lowercased().contains(text) }
    }

    var body: some View {
        let all = allVideos
        let groups = folders(all)
        let list = filtered(all)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if groups.count > 1 || !folder.isEmpty {
                    folderStrip(groups, total: all)
                }
                if list.isEmpty {
                    EmptyState(icon: "film", title: query.isEmpty ? L("Aucune vidéo") : L("Aucun résultat"),
                               subtitle: query.isEmpty ? L("Ajoutez des vidéos avec 3uTools, l'app Fichiers, ou téléchargez-les.") : "")
                        .padding(.top, 40)
                } else if grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], alignment: .leading, spacing: 18) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            GeometryReader { geometry in
                                Button {
                                    model.play(list, start: index)
                                } label: {
                                    VideoTile(track: track, width: geometry.size.width)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    TrackActions(track: track, picking: $picking, deleting: $deleting)
                                } preview: {
                                    VideoPreview(track: track)
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                    .padding(16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, onTap: { model.play(list, start: index) }) {
                                TrackActions(track: track, picking: $picking, deleting: $deleting)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground))
                            .contextMenu {
                                TrackActions(track: track, picking: $picking, deleting: $deleting)
                            } preview: {
                                VideoPreview(track: track)
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.isEmpty ? L("Vidéos") : folder)
        .searchable(text: $query, prompt: L("Rechercher dans les vidéos"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { grid.toggle() }
                } label: {
                    CircleIcon(systemName: grid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .onAppear {
            if !folder.isEmpty && !groups.contains(where: { $0.name == folder }) { folder = "" }
        }
        .trackSheets(picking: $picking, deleting: $deleting)
    }

    /// Dossiers en grandes cartes d'aperçu (comme les onglets d'Amerigo).
    private func folderStrip(_ groups: [VideoFolder], total: [Track]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FolderCard(name: L("Toutes"), items: total, selected: folder.isEmpty) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { folder = "" }
                }
                ForEach(groups) { group in
                    FolderCard(name: group.name, items: group.items, selected: folder == group.name) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { folder = group.name }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

/// Un dossier de vidéos (d'après l'emplacement du fichier dans Faxel).
struct VideoFolder: Identifiable {
    let name: String
    let items: [Track]
    var id: String { name }

    private static let leafNames: Set<String> = ["vidéos", "videos", "video", "vidéo", "audio"]

    /// Série : les épisodes dans l'ordre (S01E01, S01E02…) pour enchaîner tout seul.
    static func episodeOrder(_ list: [Track]) -> [Track] {
        let codes = list.map { SubtitleParser.episode(in: $0.fileURL.lastPathComponent) }
        guard codes.filter({ $0 != nil }).count * 2 >= list.count, list.count > 1 else { return list }
        return zip(list, codes).sorted { first, second in
            switch (first.1, second.1) {
            case let (a?, b?):
                if a.season != b.season { return a.season < b.season }
                if a.episode != b.episode { return a.episode < b.episode }
                return first.0.fileURL.lastPathComponent < second.0.fileURL.lastPathComponent
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return first.0.fileURL.lastPathComponent.localizedStandardCompare(second.0.fileURL.lastPathComponent)
                    == .orderedAscending
            }
        }
        .map { $0.0 }
    }

    private static var nameCache: [String: String] = [:]
    private static let basePath = PythonEngine.documentsURL.standardizedFileURL.resolvingSymlinksInPath().path

    static func name(of track: Track) -> String {
        if let cached = nameCache[track.path] { return cached }
        let found = computeName(track)
        nameCache[track.path] = found
        return found
    }

    private static func computeName(_ track: Track) -> String {
        let base = basePath
        let parent = track.fileURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        var parts: [String] = []
        if parent.hasPrefix(base) {
            parts = parent.dropFirst(base.count).split(separator: "/").map(String.init)
        }
        if let last = parts.last, leafNames.contains(last.lowercased()) {
            parts.removeLast()
        }
        if parts.isEmpty {
            return track.platformName.isEmpty ? L("Autres") : track.platformName
        }
        return parts.joined(separator: " › ")
    }
}

/// Grande carte d'aperçu d'un dossier : dernières miniatures, nom, nombre.
struct FolderCard: View {
    let name: String
    let items: [Track]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let first = items.first {
                    TrackArtwork(track: first, width: 118, height: 168, radius: 0)
                } else {
                    Color(.tertiarySystemFill)
                }
                if items.count > 1 {
                    HStack(spacing: 2) {
                        ForEach(Array(items.dropFirst().prefix(3)), id: \.id) { track in
                            TrackArtwork(track: track, width: 36, height: 36, radius: 6)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                    Text(L("{count} vidéo(s)", ["count": "\(items.count)"]))
                        .font(.system(size: 11))
                        .opacity(0.8)
                }
                .foregroundColor(.white)
                .padding(10)
            }
            .frame(width: 118, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.brand : Color.white.opacity(0.08), lineWidth: selected ? 3 : 1)
            )
            .scaleEffect(selected ? 1 : 0.96)
            .shadow(color: .black.opacity(0.3), radius: selected ? 10 : 4, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Aperçu animé d'une vidéo (appui long) : la vidéo joue en boucle, sans le son.
struct VideoPreview: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track

    var body: some View {
        let landscape = library.meta(track)?.isLandscape ?? true
        VStack(alignment: .leading, spacing: 0) {
            LoopingVideo(url: track.fileURL)
                .frame(width: landscape ? 340 : 260, height: landscape ? 191 : 440)
            Text(library.title(track))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .padding(12)
                .frame(width: landscape ? 340 : 260, alignment: .leading)
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// Lecture en boucle, muette, pour les aperçus.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .black
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        view.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: Surface, context: Context) {}

    static func dismantleUIView(_ uiView: Surface, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.looper?.disableLooping()
        uiView.playerLayer.player = nil
    }
}

// MARK: - Artistes et albums

struct ArtistsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared

    var body: some View {
        let artists = library.artists(model.songs)
        List {
            if artists.isEmpty {
                EmptyState(icon: "music.mic", title: L("Aucun artiste"))
                    .listRowSeparator(.hidden)
            }
            ForEach(artists) { artist in
                NavigationLink(value: LibraryRoute.artist(artist.id)) {
                    HStack(spacing: 14) {
                        Artwork(url: artist.artwork, seed: artist.id, icon: "music.mic", width: 54, height: 54, radius: 27)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name)
                                .font(.system(size: 16, weight: .medium))
                            Text(artist.subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Artistes"))
    }
}

struct AlbumsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared

    var body: some View {
        let albums = library.albums(model.songs)
        ScrollView {
            if albums.isEmpty {
                EmptyState(icon: "square.stack", title: L("Aucun album"),
                           subtitle: L("Les albums viennent des informations des fichiers (balises album)."))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      alignment: .leading, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: LibraryRoute.album(album.id)) {
                        GeometryReader { geometry in
                            CoverTile(title: album.name, subtitle: album.subtitle, artwork: album.artwork, seed: album.id,
                                      icon: "square.stack.fill", size: geometry.size.width)
                        }
                        .frame(height: 210)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(L("Albums"))
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    let id: String
    @State private var picking: Track?
    @State private var deleting: Track?

    var body: some View {
        let album = library.albums(model.songs).first { $0.id == id }
        let tracks = album?.tracks ?? []
        List {
            VStack(spacing: 10) {
                Artwork(url: album?.artwork, seed: id, icon: "square.stack.fill", width: 240, height: 240, radius: 14)
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                Text(album?.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(album?.subtitle ?? "")
                    .font(.system(size: 18))
                    .foregroundColor(.brand)
                Text(L("{count} titre(s) · {time}", ["count": "\(tracks.count)",
                                                      "time": Fmt.duration(tracks.compactMap { library.duration($0) }.reduce(0, +))]))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                PlayShuffleButtons(tracks: tracks)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, number: library.meta(track)?.trackNumber ?? index + 1,
                         onTap: { model.play(tracks, start: index) }) {
                    TrackActions(track: track, picking: $picking, deleting: $deleting)
                }
                .contextMenu {
                    TrackActions(track: track, picking: $picking, deleting: $deleting)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .trackSheets(picking: $picking, deleting: $deleting)
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    let id: String
    @State private var picking: Track?
    @State private var deleting: Track?

    var body: some View {
        let artist = library.artists(model.songs).first { $0.id == id }
        let tracks = artist?.tracks ?? []
        let albums = library.albums(tracks)
        List {
            VStack(spacing: 10) {
                Artwork(url: artist?.artwork, seed: id, icon: "music.mic", width: 170, height: 170, radius: 85)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                Text(artist?.name ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                PlayShuffleButtons(tracks: tracks)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
            if !albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(albums) { album in
                                NavigationLink(value: LibraryRoute.album(album.id)) {
                                    CoverTile(title: album.name, subtitle: "", artwork: album.artwork, seed: album.id,
                                              icon: "square.stack.fill", size: 140)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text(L("Albums"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }
            Section {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, onTap: { model.play(tracks, start: index) }) {
                        TrackActions(track: track, picking: $picking, deleting: $deleting)
                    }
                    .contextMenu {
                        TrackActions(track: track, picking: $picking, deleting: $deleting)
                    }
                }
            } header: {
                Text(L("Morceaux"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .trackSheets(picking: $picking, deleting: $deleting)
    }
}

// MARK: - Téléchargés

struct DownloadsListView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("downloadsFilter") private var filter = "all"
    @State private var picking: Track?
    @State private var deleting: Track?
    @State private var confirmClear = false
    @State private var previewItems: [URL] = []
    @State private var previewURL: URL?

    private var shown: [Track] {
        let list = model.downloads
        switch filter {
        case "video": return list.filter { $0.kind != "audio" }
        case "audio": return list.filter { $0.kind == "audio" }
        default: return list
        }
    }

    var body: some View {
        let list = shown
        List {
            Picker("", selection: $filter) {
                Text(L("Tout")).tag("all")
                Text(L("Vidéos")).tag("video")
                Text(L("Audio")).tag("audio")
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            if list.isEmpty {
                EmptyState(icon: "arrow.down.circle", title: L("Vos téléchargements apparaîtront ici."),
                           subtitle: L("Collez un lien dans l'onglet Télécharger."))
                    .listRowSeparator(.hidden)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, onTap: { open(track, in: list, at: index) }) {
                    TrackActions(track: track, picking: $picking, deleting: $deleting)
                }
                .contextMenu {
                    TrackActions(track: track, picking: $picking, deleting: $deleting)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleting = track
                    } label: {
                        Label(L("Supprimer"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Téléchargés"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label(L("Effacer l'historique"), systemImage: "trash")
                    }
                } label: {
                    CircleIcon(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog(L("Effacer l'historique"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("Effacer l'historique"), role: .destructive) { model.clearHistory() }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("La liste sera vidée puis reconstruite à partir des fichiers présents. Les fichiers, playlists et le Coffre ne changent pas."))
        }
        .trackSheets(picking: $picking, deleting: $deleting)
        .quickLookPreview($previewURL, in: previewItems)
    }

    private func open(_ track: Track, in list: [Track], at index: Int) {
        if track.isFolder {
            let photos = track.photoURLs
            guard let first = photos.first else {
                model.show(L("Fichier introuvable (supprimé ou déplacé)."), .warn)
                return
            }
            previewItems = photos
            previewURL = first
        } else {
            model.play(list, start: index)
        }
    }
}

/// Favoris, Coffre ou une playlist.
struct CollectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let route: LibraryRoute
    @State private var picking: Track?
    @State private var deleting: Track?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var previewItems: [URL] = []
    @State private var previewURL: URL?

    private var playlist: Playlist? {
        if case .playlist(let id) = route { return model.playlist(id) }
        return nil
    }

    private var isVault: Bool {
        if case .vault = route { return true }
        return false
    }

    private var title: String {
        switch route {
        case .favorites: return L("Favoris")
        case .vault: return L("Coffre")
        default: return playlist?.name ?? L("Playlist")
        }
    }

    private var tracks: [Track] {
        switch route {
        case .favorites: return model.favoriteTracks
        case .vault: return model.vaultUnlocked ? model.vault : []
        default: return playlist?.items ?? []
        }
    }

    var body: some View {
        List {
            if isVault && !model.vaultUnlocked {
                VStack(spacing: 16) {
                    EmptyState(icon: "lock.fill", title: L("Coffre verrouillé"),
                               subtitle: L("Identifiez-vous avec Face ID pour voir vos fichiers privés."))
                    Button(L("Déverrouiller")) {
                        model.unlockVault {}
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 50)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                if isVault {
                    Text(L("Les fichiers du Coffre sont cachés de la Bibliothèque et de l'app Fichiers. Le Coffre se reverrouille dès que vous le quittez."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .listRowSeparator(.hidden)
                }
                let list = tracks
                if !list.isEmpty {
                    PlayShuffleButtons(tracks: list)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if list.isEmpty {
                    EmptyState(icon: isVault ? "lock" : "rectangle.stack", title: L("Aucun élément"), subtitle: emptyText)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, onTap: { open(track, in: list, at: index) }) {
                            menu(for: track)
                        }
                        .contextMenu {
                            menu(for: track)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                remove(track)
                            } label: {
                                Label(removeLabel, systemImage: isVault ? "lock.open" : "minus.circle")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let playlist = playlist {
                    Menu {
                        Button {
                            newName = playlist.name
                            renaming = true
                        } label: {
                            Label(L("Renommer"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(L("Supprimer la playlist"), systemImage: "trash")
                        }
                    } label: {
                        CircleIcon(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert(L("Renommer"), isPresented: $renaming) {
            TextField(L("Nom de la playlist"), text: $newName)
            Button(L("Annuler"), role: .cancel) {}
            Button(L("OK")) {
                if let playlist = playlist { model.renamePlaylist(playlist, to: newName) }
            }
        }
        .confirmationDialog(L("Supprimer la playlist ?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Supprimer"), role: .destructive) {
                if let playlist = playlist {
                    model.deletePlaylist(playlist)
                    dismiss()
                }
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Les fichiers restent dans votre bibliothèque."))
        }
        .trackSheets(picking: $picking, deleting: $deleting)
        .quickLookPreview($previewURL, in: previewItems)
        .onDisappear {
            if isVault { model.lockVault() }
        }
    }

    private var emptyText: String {
        switch route {
        case .vault: return L("Rangez ici vos fichiers privés : ⋯ puis « Mettre au Coffre » dans la Bibliothèque.")
        case .favorites: return L("Touchez ⋯ puis « Favori » sur un morceau ou une vidéo pour le retrouver ici.")
        default: return L("Ajoutez des morceaux depuis la Bibliothèque : ⋯ puis « Ajouter à une playlist ».")
        }
    }

    private var removeLabel: String {
        isVault ? L("Sortir du Coffre") : L("Retirer")
    }

    @ViewBuilder
    private func menu(for track: Track) -> some View {
        if track.exists && !isVault && track.isAudio {
            Button {
                model.playNext(track)
            } label: {
                Label(L("Lire ensuite"), systemImage: "text.insert")
            }
        }
        if track.exists && !isVault {
            ShareLink(item: track.fileURL) {
                Label(L("Partager"), systemImage: "square.and.arrow.up")
            }
        }
        Button {
            remove(track)
        } label: {
            Label(removeLabel, systemImage: isVault ? "lock.open" : "minus.circle")
        }
        if isVault {
            Button(role: .destructive) {
                deleting = track
            } label: {
                Label(L("Supprimer"), systemImage: "trash")
            }
        }
    }

    private func open(_ track: Track, in list: [Track], at index: Int) {
        if track.isFolder {
            let photos = track.photoURLs
            guard let first = photos.first else { return }
            previewItems = photos
            previewURL = first
        } else {
            model.play(list, start: index)
        }
    }

    private func remove(_ track: Track) {
        switch route {
        case .favorites:
            model.toggleFavorite(track)
        case .vault:
            model.removeFromVault(track)
        case .playlist:
            if let playlist = playlist { model.remove(track, from: playlist) }
        default:
            break
        }
    }
}

/// Explorateur des fichiers de Faxel (comme l'app Fichiers) : on y voit aussi ce qui a été copié avec 3uTools.
struct FilesView: View {
    @EnvironmentObject var model: AppModel
    let path: String
    @State private var entries: [URL] = []
    @State private var previewURL: URL?
    @State private var importing = false

    private var title: String {
        path == PythonEngine.documentsURL.path ? L("Fichiers") : (path as NSString).lastPathComponent
    }

    var body: some View {
        List {
            if entries.isEmpty {
                EmptyState(icon: "folder", title: L("Dossier vide"))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(entries, id: \.self) { url in
                    if isDirectory(url) {
                        NavigationLink(value: LibraryRoute.files(url.path)) {
                            fileRow(url, icon: "folder.fill", color: .blue,
                                    detail: L("{count} élément(s)", ["count": "\(count(url))"]))
                        }
                    } else {
                        Button {
                            open(url)
                        } label: {
                            fileRow(url, icon: icon(for: url), color: .brand, detail: Fmt.size(fileSize(url.path)))
                        }
                        .foregroundColor(.primary)
                        .swipeActions {
                            ShareLink(item: url) {
                                Label(L("Partager"), systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        importing = true
                    } label: {
                        Label(L("Importer depuis Fichiers"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        model.openInFiles()
                    } label: {
                        Label(L("Ouvrir dans Fichiers"), systemImage: "folder")
                    }
                } label: {
                    CircleIcon(systemName: "ellipsis")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie, .data, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.importFiles(urls)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { reload() }
            }
        }
        .onAppear(perform: reload)
        .refreshable {
            await MainActor.run {
                reload()
                model.rescan(force: true)
            }
        }
        .quickLookPreview($previewURL, in: entries.filter { !isDirectory($0) })
    }

    private func reload() {
        let base = URL(fileURLWithPath: path)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let urls = names.filter { !$0.hasPrefix(".") }.map { base.appendingPathComponent($0) }
        entries = urls.sorted { lhs, rhs in
            let left = isDirectory(lhs)
            let right = isDirectory(rhs)
            if left != right { return left }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    private func count(_ url: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.count
    }

    private func icon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return "film" }
        if audioExtensions.contains(ext) { return "music.note" }
        if imageExtensions.contains(ext) { return "photo" }
        if subtitleExtensions.contains(ext) { return "captions.bubble" }
        return "doc"
    }

    private func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
            model.playFile(url)
        } else {
            previewURL = url
        }
    }

    private func fileRow(_ url: URL, icon: String, color: Color, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 15))
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// Le moteur Python n'a pas démarré : on affiche l'erreur exacte (une capture suffit pour corriger).
struct EngineErrorCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Le moteur de téléchargement n'a pas démarré"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.orange)
            Text(L("Faites une capture de cet écran et envoyez-la : elle indique exactement ce qui bloque."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(14)
        }
        .padding(.vertical, 6)
    }
}
