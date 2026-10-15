import AVKit
import SwiftUI

extension Color {
    /// Couleur d'accent de Faxel (violet #8B5CF6).
    static let brand = Color(red: 139.0 / 255.0, green: 92.0 / 255.0, blue: 246.0 / 255.0)
    static let brandPink = Color(red: 236.0 / 255.0, green: 72.0 / 255.0, blue: 153.0 / 255.0)
}

// MARK: - Miniatures

private let artworkPalettes: [[Color]] = [
    [Color(red: 1.0, green: 0.62, blue: 0.04), Color(red: 0.90, green: 0.30, blue: 0.15)],
    [Color(red: 0.35, green: 0.35, blue: 0.95), Color(red: 0.62, green: 0.25, blue: 0.85)],
    [Color(red: 0.10, green: 0.70, blue: 0.65), Color(red: 0.15, green: 0.35, blue: 0.70)],
    [Color(red: 0.95, green: 0.35, blue: 0.60), Color(red: 0.98, green: 0.65, blue: 0.35)],
    [Color(red: 0.30, green: 0.75, blue: 0.40), Color(red: 0.10, green: 0.45, blue: 0.40)],
    [Color(red: 0.25, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.45, blue: 0.30)],
]

func artworkColors(_ seed: String) -> [Color] {
    var hash: UInt32 = 5381
    for byte in seed.utf8 {
        hash = (hash &* 33) &+ UInt32(byte)
    }
    return artworkPalettes[Int(hash % UInt32(artworkPalettes.count))]
}

/// Miniature : pochette du fichier, image en ligne, sinon un dégradé avec une icône.
struct Artwork: View {
    let url: String?
    let seed: String
    var icon: String = "play.rectangle.fill"
    var width: CGFloat? = 84
    var height: CGFloat? = 56
    var radius: CGFloat = 9

    var body: some View {
        ZStack {
            LinearGradient(colors: artworkColors(seed), startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: min(width ?? 120, height ?? 120) * 0.34, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            if let link = url, let address = URL(string: link) {
                LocalImage(url: address)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Image enregistrée sur l'iPhone (pochette, aperçu vidéo).
struct LocalImage: View {
    let url: URL
    @State private var image: UIImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageCache.shared.image(url))
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        if let cached = ImageCache.shared.image(url) {
            image = cached
            return
        }
        let wanted = url
        ImageCache.shared.load(wanted) { loaded in
            if wanted == url { image = loaded }
        }
    }
}

/// Pochette carrée d'un morceau ou image d'une vidéo, à partir de la bibliothèque.
struct TrackArtwork: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track
    var width: CGFloat? = 52
    var height: CGFloat? = 52
    var radius: CGFloat = 8

    var body: some View {
        Artwork(url: library.artwork(track), seed: track.id, icon: track.isAudio ? "music.note" : track.icon,
                width: width, height: height, radius: radius)
    }
}

/// Petit indicateur « en cours de lecture » (barres animées).
struct PlayingBars: View {
    var playing: Bool
    var color: Color = .brand
    @State private var animate = false
    private static let high: [CGFloat] = [12, 6, 10]
    private static let low: [CGFloat] = [5, 9, 4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: animate && playing ? PlayingBars.high[index] : PlayingBars.low[index])
            }
        }
        .frame(width: 16, height: 14, alignment: .bottom)
        .animation(playing ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: animate)
        .onAppear { animate = true }
    }
}

/// Bouton AirPlay natif (enceinte, Apple TV).
struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor = .label
    var video = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = UIColor(red: 139.0 / 255.0, green: 92.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
        view.prioritizesVideoDevices = video
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
    }
}

// MARK: - Lignes

/// Ligne d'un morceau (pochette carrée) ou d'une vidéo (image 16:9), avec menu ⋯.
struct TrackRow<MenuContent: View>: View {
    @ObservedObject private var library = MediaLibrary.shared
    @EnvironmentObject var player: AudioPlayer
    let track: Track
    var number: Int? = nil
    let onTap: () -> Void
    @ViewBuilder var menu: () -> MenuContent

    private var isCurrent: Bool {
        player.current?.path == track.path
    }

    private var titleColor: Color {
        if !track.exists { return Color.secondary }
        return isCurrent ? Color.brand : Color.primary
    }

    var body: some View {
        HStack(spacing: 12) {
            if let number = number {
                Text("\(number)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            ZStack {
                if track.isAudio {
                    TrackArtwork(track: track, width: 50, height: 50, radius: 7)
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        TrackArtwork(track: track, width: 88, height: 52, radius: 8)
                        let time = Fmt.duration(library.duration(track))
                        if !time.isEmpty {
                            Text(time)
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.65)))
                                .padding(3)
                        }
                    }
                }
                if isCurrent {
                    RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35))
                        .frame(width: track.isAudio ? 50 : 88, height: track.isAudio ? 50 : 52)
                    PlayingBars(playing: player.isPlaying, color: .white)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(library.title(track))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(titleColor)
                Text(track.exists ? library.subtitle(track) : L("Supprimé ou déplacé"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Actions d'un fichier de la bibliothèque (menu ⋯ et appui long).
struct TrackActions: View {
    @EnvironmentObject var model: AppModel
    let track: Track
    @Binding var picking: Track?
    @Binding var deleting: Track?

    var body: some View {
        if track.exists {
            if track.isAudio {
                Button {
                    model.playNext(track)
                } label: {
                    Label(L("Lire ensuite"), systemImage: "text.insert")
                }
                Button {
                    model.addToQueue(track)
                } label: {
                    Label(L("Ajouter à la file de lecture"), systemImage: "text.append")
                }
            }
            Button {
                model.toggleFavorite(track)
            } label: {
                if model.isFavorite(track) {
                    Label(L("Retirer des favoris"), systemImage: "heart.slash")
                } else {
                    Label(L("Favori"), systemImage: "heart")
                }
            }
            Button {
                picking = track
            } label: {
                Label(L("Ajouter à une playlist"), systemImage: "text.badge.plus")
            }
            AddToVirtualFolderMenu(track: track)
            CoverMenuItems(track: track)
            if track.isVideo {
                Button {
                    WatermarkCenter.shared.track = track
                } label: {
                    Label(L("Retirer un filigrane…"), systemImage: "wand.and.stars")
                }
            }
            if track.isFolder {
                ShareLink(items: track.photoURLs) {
                    Label(L("Partager"), systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: track.fileURL) {
                    Label(L("Partager"), systemImage: "square.and.arrow.up")
                }
            }
            if track.isVideo {
                Button {
                    model.saveToPhotos(track)
                } label: {
                    Label(L("Enregistrer dans Photos"), systemImage: "photo.on.rectangle")
                }
            }
            if !track.isFolder {
                Button {
                    model.compress(track)
                } label: {
                    Label(L("Compresser"), systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }
            Button {
                model.moveToVault(track)
            } label: {
                Label(L("Mettre au Coffre"), systemImage: "lock")
            }
            Divider()
        }
        Button(role: .destructive) {
            deleting = track
        } label: {
            Label(L("Supprimer"), systemImage: "trash")
        }
    }
}

/// Carte d'un téléchargement de la file.
struct JobCard: View {
    @EnvironmentObject var model: AppModel
    let job: Job

    private var statusColor: Color {
        switch job.status {
        case "done": return .green
        case "failed": return .red
        case "waiting", "retrying", "skipped": return .orange
        case "downloading", "processing": return .brand
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Artwork(url: job.thumbnail, seed: job.url, icon: job.mediaType == "audio" ? "music.note" : "play.rectangle.fill",
                        width: 72, height: 48, radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(job.info)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if job.active || job.isPaused {
                ProgressView(value: max(0, min(1, job.fraction)))
                    .tint(.brand)
            }
            Text(job.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(statusColor)
            if !job.message.isEmpty && (job.isFailed || job.status == "retrying" || job.status == "waiting") {
                Text(L(job.message))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(5)
            }
            HStack(spacing: 8) {
                if job.isDone, let path = job.filepath {
                    smallButton(L("Lire"), icon: "play.fill") {
                        model.playFile(URL(fileURLWithPath: path))
                    }
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Label(L("Partager"), systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.tertiarySystemFill)))
                    }
                    .foregroundColor(.brand)
                } else if job.active {
                    smallButton(L("Pause"), icon: "pause.fill") { model.jobAction("pause", job) }
                    smallButton(L("Annuler"), icon: "xmark", role: .red) { model.jobAction("cancel", job) }
                } else if job.isPaused {
                    smallButton(L("Reprendre"), icon: "play.fill") { model.jobAction("resume", job) }
                    smallButton(L("Annuler"), icon: "xmark", role: .red) { model.jobAction("cancel", job) }
                } else if job.isSkipped {
                    smallButton(L("Retélécharger"), icon: "arrow.down.circle") {
                        model.jobAction("retry", job, force: true)
                    }
                } else {
                    smallButton(L("Réessayer"), icon: "arrow.clockwise") { model.jobAction("retry", job) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func smallButton(_ title: String, icon: String, role: Color = .brand,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(role)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tuiles, boutons, états

/// Grande tuile arrondie (« Navigateur », « Coffre », « Fichiers »).
struct Tile: View {
    let icon: String
    let title: String
    var tint: Color = .brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(tint)
                HStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tint.opacity(0.13))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Bouton rond de la barre du haut (« + », « ⋯ »), comme dans Elara.
struct CircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.brand)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color(.tertiarySystemFill)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(filled ? .white : .brand)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? Color.brand : Color(.tertiarySystemFill))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .regular))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// Icône colorée des Réglages (carré arrondi, comme iOS).
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
    }
}

struct SettingsLabel: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIcon(systemName: icon, color: color)
        }
    }
}

/// Bandeau de message en haut de l'écran.
struct ToastBanner: View {
    let toast: Toast

    private var icon: (String, Color) {
        switch toast.kind {
        case .ok: return ("checkmark.circle.fill", .green)
        case .warn: return ("exclamationmark.triangle.fill", .orange)
        case .error: return ("xmark.octagon.fill", .red)
        case .info: return ("info.circle.fill", .brand)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.0)
                .foregroundColor(icon.1)
                .font(.system(size: 18))
            Text(toast.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - Choix d'une playlist, suppression

struct PlaylistPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Artwork(url: track.thumbnail, seed: track.id, icon: track.icon, width: 60, height: 40, radius: 7)
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                    }
                }
                if !model.playlists.isEmpty {
                    Section(L("Mes playlists")) {
                        ForEach(model.playlists) { playlist in
                            Button {
                                model.add(track, to: playlist)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.stack.fill")
                                        .foregroundColor(.brand)
                                        .frame(width: 28)
                                    Text(playlist.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(playlist.items.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Section(L("Nouvelle playlist")) {
                    HStack {
                        TextField(L("Nom de la nouvelle playlist"), text: $newName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Button(L("Créer"), action: create)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .navigationTitle(L("Ajouter à une playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        model.createPlaylist(newName, adding: track)
        dismiss()
    }
}

/// Choix de playlist et confirmation de suppression (fichier ou seulement la ligne).
struct TrackSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var picking: Track?
    @Binding var deleting: Track?

    func body(content: Content) -> some View {
        content
            .sheet(item: $picking) { track in
                PlaylistPicker(track: track)
                    .environmentObject(model)
            }
            .confirmationDialog(
                L("Supprimer ?"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { track in
                Button(L("Supprimer le fichier"), role: .destructive) {
                    model.delete(track, deleteFile: true)
                    deleting = nil
                }
                Button(L("Retirer de la liste seulement")) {
                    model.delete(track, deleteFile: false)
                    deleting = nil
                }
                Button(L("Annuler"), role: .cancel) {
                    deleting = nil
                }
            } message: { track in
                Text(track.title)
            }
    }
}

extension View {
    func trackSheets(picking: Binding<Track?>, deleting: Binding<Track?>) -> some View {
        modifier(TrackSheets(picking: picking, deleting: deleting))
    }
}

// MARK: - Grilles et en-têtes (style Musique)

/// Titre de section avec « Tout voir ».
struct SectionTitle: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Spacer()
            if let action = action {
                Button(L("Tout voir"), action: action)
                    .font(.system(size: 16))
                    .foregroundColor(.brand)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Carré d'album, d'artiste ou de playlist (pochette + nom + détail).
struct CoverTile: View {
    let title: String
    let subtitle: String
    let artwork: String?
    let seed: String
    var icon: String = "music.note"
    var size: CGFloat = 160
    var round = false

    var body: some View {
        VStack(alignment: round ? .center : .leading, spacing: 5) {
            Artwork(url: artwork, seed: seed, icon: icon, width: size, height: size, radius: round ? size / 2 : 10)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: size, alignment: round ? .center : .leading)
    }
}

/// Vignette 16:9 d'une vidéo (titre en dessous).
struct VideoTile: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track
    var width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                TrackArtwork(track: track, width: width, height: width * 9 / 16, radius: 10)
                let time = Fmt.duration(library.duration(track))
                if !time.isEmpty {
                    Text(time)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.65)))
                        .padding(5)
                }
            }
            Text(library.title(track))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !track.platformName.isEmpty {
                Text(track.platformName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Boutons « Lecture » et « Aléatoire » (en-tête d'album, de playlist…).
struct PlayShuffleButtons: View {
    @EnvironmentObject var model: AppModel
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.play(tracks, start: 0)
            } label: {
                Label(L("Lecture"), systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
            Button {
                model.shuffle(tracks)
            } label: {
                Label(L("Aléatoire"), systemImage: "shuffle")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .disabled(tracks.isEmpty)
    }
}
