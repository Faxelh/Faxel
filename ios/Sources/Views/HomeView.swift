import SwiftUI

/// Onglet Accueil : écoutés récemment, ajoutés récemment, albums, vidéos,
/// playlists et artistes, comme la page d'accueil de Musique.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: AudioPlayer
    @ObservedObject private var library = MediaLibrary.shared
    @State private var importing = false
    @State private var showCompressor = false
    @AppStorage("faxelProfileName") private var profileName = "Faxel"
    @AppStorage("faxelProfilePhotoPath") private var profilePhotoPath = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 || hour >= 18 { return L("Bonsoir,") }
        if hour >= 12 { return L("Bon après-midi,") }
        return L("Bonjour,")
    }

    private var dateHeading: String {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).uppercased(with: Lang.locale)
    }

    @ViewBuilder
    private var profileImage: some View {
        if !profilePhotoPath.isEmpty, let image = UIImage(contentsOfFile: profilePhotoPath) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image("Logo").resizable().scaledToFill()
        }
    }

    private var welcomeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dateHeading)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                (Text(greeting) + Text("\n" + profileName))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { model.showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            Button { model.tab = .settings } label: {
                profileImage
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 6)
    }

    var body: some View {
        NavigationStack(path: $model.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    welcomeHeader
                    if let error = model.engineError {
                        EngineErrorCard(message: error)
                            .padding(.horizontal, 16)
                    }
                    quickActions
                    Button { showCompressor = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(Color.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L("Compresser une vidéo"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(L("Créer une version plus légère sans remplacer l'original"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    content
                }
                .padding(.vertical, 8)
                .padding(.bottom, 20)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        CircleIcon(systemName: "square.and.arrow.down")
                    }
                }
            }
            .refreshable {
                await MainActor.run { model.rescan(force: true) }
            }
            .libraryDestinations()
            .importer(isPresented: $importing)
            .sheet(isPresented: $showCompressor) {
                CompressionView()
                    .environmentObject(model)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                model.shuffle(model.songs)
            } label: {
                Label(L("Aléatoire"), systemImage: "shuffle")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                model.shuffle(model.favoriteTracks.filter { $0.isAudio })
            } label: {
                Label(L("Mes favoris"), systemImage: "heart.fill")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(.horizontal, 16)
        .disabled(model.songs.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        let songs = model.songs
        let videos = model.videos
        if songs.isEmpty && videos.isEmpty {
            if model.libraryLoaded || model.engineError != nil {
                AddMusicCard(importing: $importing)
                    .padding(.horizontal, 16)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            }
        } else {
            let recentPlayed = player.recent.compactMap { path in songs.first { $0.path == path } }
            if !recentPlayed.isEmpty {
                shelf(L("Écoutés récemment"), route: nil) {
                    ForEach(Array(recentPlayed.prefix(15).enumerated()), id: \.element.id) { index, track in
                        Button {
                            model.play(Array(recentPlayed.prefix(15)), start: index)
                        } label: {
                            CoverTile(title: library.title(track), subtitle: library.artist(track),
                                      artwork: library.artwork(track), seed: track.id, size: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let added = songs.sorted { $0.addedDate > $1.addedDate }
            if !added.isEmpty {
                shelf(L("Musique ajoutée récemment"), route: .songs) {
                    ForEach(Array(added.prefix(15).enumerated()), id: \.element.id) { index, track in
                        Button {
                            model.play(Array(added.prefix(15)), start: index)
                        } label: {
                            CoverTile(title: library.title(track), subtitle: library.artist(track),
                                      artwork: library.artwork(track), seed: track.id, size: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let recentVideos = videos.sorted { $0.addedDate > $1.addedDate }
            if !recentVideos.isEmpty {
                shelf(L("Vidéos"), route: .videos) {
                    ForEach(Array(recentVideos.prefix(12).enumerated()), id: \.element.id) { index, track in
                        Button {
                            model.play(recentVideos, start: index)
                        } label: {
                            VideoTile(track: track, width: 230)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let albums = library.albums(songs)
            if !albums.isEmpty {
                shelf(L("Albums"), route: .albums) {
                    ForEach(albums.prefix(15)) { album in
                        NavigationLink(value: LibraryRoute.album(album.id)) {
                            CoverTile(title: album.name, subtitle: album.subtitle, artwork: album.artwork,
                                      seed: album.id, icon: "square.stack.fill", size: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.playlists.isEmpty {
                shelf(L("Mes playlists"), route: .playlists) {
                    ForEach(model.playlists) { playlist in
                        NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                            CoverTile(title: playlist.name,
                                      subtitle: L("{count} élément(s)", ["count": "\(playlist.items.count)"]),
                                      artwork: playlist.items.lazy.compactMap { library.artwork($0) }.first,
                                      seed: playlist.id, icon: "music.note.list", size: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let artists = library.artists(songs)
            if artists.count > 1 {
                shelf(L("Artistes"), route: .artists) {
                    ForEach(artists.prefix(15)) { artist in
                        NavigationLink(value: LibraryRoute.artist(artist.id)) {
                            CoverTile(title: artist.name, subtitle: "", artwork: artist.artwork, seed: artist.id,
                                      icon: "music.mic", size: 110, round: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shelf<Items: View>(_ title: String, route: LibraryRoute?,
                                    @ViewBuilder items: () -> Items) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let route = route {
                NavigationLink(value: route) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    items()
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
