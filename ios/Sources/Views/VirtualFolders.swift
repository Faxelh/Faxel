import SwiftUI
import UniformTypeIdentifiers

/// Dossier virtuel (comme dans Amerigo) : un regroupement libre de vidéos,
/// musiques et fichiers, sans déplacer les fichiers eux-mêmes.
struct VirtualFolder: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var paths: [String] = []
    var created = Date()
}

/// Dossiers virtuels, enregistrés dans Faxel (virtual_folders.json).
final class VirtualFolderStore: ObservableObject {
    static let shared = VirtualFolderStore()

    @Published private(set) var folders: [VirtualFolder] = []

    private var fileURL: URL {
        PythonEngine.dataURL.appendingPathComponent("virtual_folders.json")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([VirtualFolder].self, from: data) {
            folders = saved
        }
    }

    private func save() {
        let snapshot = folders
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func folder(_ id: String) -> VirtualFolder? {
        folders.first { $0.id == id }
    }

    @discardableResult
    func create(_ name: String) -> VirtualFolder {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = VirtualFolder(name: clean.isEmpty ? L("Nouveau dossier") : clean)
        folders.insert(folder, at: 0)
        save()
        return folder
    }

    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = clean
        save()
    }

    func delete(_ id: String) {
        folders.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func add(_ paths: [String], to id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        var list = folders[index].paths
        for path in paths where !list.contains(path) {
            list.append(path)
        }
        folders[index].paths = list
        save()
    }

    func remove(_ path: String, from id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].paths.removeAll { $0 == path }
        save()
    }

    func contains(_ path: String, in id: String) -> Bool {
        folder(id)?.paths.contains(path) ?? false
    }

    /// Les éléments du dossier qui existent encore dans la bibliothèque.
    func items(_ folder: VirtualFolder, in tracks: [Track]) -> [Track] {
        let byPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return folder.paths.compactMap { byPath[$0] }
    }
}

// MARK: - Liste des dossiers virtuels

struct VirtualFoldersView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = VirtualFolderStore.shared
    @State private var creating = false
    @State private var renaming: VirtualFolder?
    @State private var managing: VirtualFolder?
    @State private var deleting: VirtualFolder?
    @State private var addingFrom: VirtualFolder?
    @State private var importingInto: VirtualFolder?
    @State private var importing = false
    @State private var name = ""

    var body: some View {
        Group {
            if store.folders.isEmpty {
                empty
            } else {
                List {
                    ForEach(store.folders) { folder in
                        NavigationLink(value: LibraryRoute.virtualFolder(folder.id)) {
                            row(folder)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleting = folder
                            } label: {
                                Label(L("Supprimer"), systemImage: "trash")
                            }
                            Button {
                                name = folder.name
                                renaming = folder
                            } label: {
                                Label(L("Renommer"), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L("Dossiers virtuels"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    name = ""
                    creating = true
                } label: {
                    CircleIcon(systemName: "plus")
                }
            }
            if !store.folders.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .alert(L("Nouveau dossier virtuel"), isPresented: $creating) {
            TextField(L("Nom du dossier"), text: $name)
            Button(L("Annuler"), role: .cancel) {}
            Button(L("Créer")) {
                let folder = store.create(name)
                model.libraryPath.append(.virtualFolder(folder.id))
            }
        }
        .alert(L("Renommer le dossier virtuel"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(L("Nom du dossier"), text: $name)
            Button(L("Annuler"), role: .cancel) { renaming = nil }
            Button(L("Renommer")) {
                if let folder = renaming { store.rename(folder.id, to: name) }
                renaming = nil
            }
        }
        .confirmationDialog(managing?.name ?? "", isPresented: Binding(
            get: { managing != nil }, set: { if !$0 { managing = nil } }
        ), titleVisibility: .visible) {
            if let folder = managing {
                VirtualFolderMenu(folder: folder, name: $name, renaming: $renaming, deleting: $deleting,
                                  addingFrom: $addingFrom, importingInto: $importingInto, importing: $importing)
            }
        } message: {
            Text(L("Gérer le dossier virtuel"))
        }
        .confirmationDialog(L("Supprimer « {name} » ?", ["name": deleting?.name ?? ""]), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button(L("Supprimer le dossier virtuel"), role: .destructive) {
                if let folder = deleting { store.delete(folder.id) }
                deleting = nil
            }
        } message: {
            Text(L("Les fichiers ne sont pas supprimés : ils restent dans la bibliothèque."))
        }
        .sheet(item: $addingFrom) { folder in
            LibraryPicker(folder: folder)
                .environmentObject(model)
        }
        .virtualImporter(isPresented: $importing, folder: $importingInto)
    }

    private func row(_ folder: VirtualFolder) -> some View {
        let items = store.items(folder, in: model.tracks)
        return HStack(spacing: 14) {
            ZStack {
                if let first = items.first {
                    TrackArtwork(track: first, width: 56, height: 56, radius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.brand.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 22))
                        .foregroundColor(.brand)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(items.isEmpty ? L("Aucun élément") : L("{count} élément(s)", ["count": "\(items.count)"]))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                managing = folder
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.brand)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox.fill")
                .font(.system(size: 72))
                .foregroundColor(.brand)
            Text(L("Vous n'avez pas encore créé de dossier…"))
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.brand)
                .multilineTextAlignment(.center)
            Text(L("Les dossiers virtuels regroupent vos vidéos, musiques et fichiers comme vous le voulez, sans les déplacer : un même fichier peut être dans plusieurs dossiers."))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                name = ""
                creating = true
            } label: {
                Text(L("Créer un dossier virtuel"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 60)
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
    }
}

/// Actions d'un dossier virtuel (feuille « Gérer le dossier virtuel »).
struct VirtualFolderMenu: View {
    let folder: VirtualFolder
    @Binding var name: String
    @Binding var renaming: VirtualFolder?
    @Binding var deleting: VirtualFolder?
    @Binding var addingFrom: VirtualFolder?
    @Binding var importingInto: VirtualFolder?
    @Binding var importing: Bool

    var body: some View {
        Button {
            addingFrom = folder
        } label: {
            Label(L("Ajouter depuis la bibliothèque"), systemImage: "iphone")
        }
        Button {
            importingInto = folder
            importing = true
        } label: {
            Label(L("Ajouter depuis Fichiers et Clouds"), systemImage: "icloud")
        }
        Button {
            name = folder.name
            renaming = folder
        } label: {
            Label(L("Renommer le dossier virtuel"), systemImage: "character.cursor.ibeam")
        }
        Button(role: .destructive) {
            deleting = folder
        } label: {
            Label(L("Supprimer le dossier virtuel"), systemImage: "trash")
        }
    }
}

/// Import depuis l'app Fichiers (iCloud Drive, Google Drive, Dropbox…) directement dans un dossier virtuel.
struct VirtualImporterModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    @Binding var folder: VirtualFolder?

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.audio, .movie, .data, .folder],
                             allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, let target = folder else { return }
            model.importFiles(urls) { paths in
                VirtualFolderStore.shared.add(paths, to: target.id)
            }
            folder = nil
        }
    }
}

extension View {
    func virtualImporter(isPresented: Binding<Bool>, folder: Binding<VirtualFolder?>) -> some View {
        modifier(VirtualImporterModifier(isPresented: isPresented, folder: folder))
    }
}

// MARK: - Contenu d'un dossier virtuel

struct VirtualFolderView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = VirtualFolderStore.shared
    @ObservedObject private var library = MediaLibrary.shared
    let id: String

    @AppStorage("virtualGrid") private var grid = true
    @State private var picking: Track?
    @State private var deleting: Track?
    @State private var adding = false
    @State private var importing = false
    @State private var importingInto: VirtualFolder?
    @State private var renaming: VirtualFolder?
    @State private var removingFolder: VirtualFolder?
    @State private var managing = false
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let folder = store.folder(id) {
            content(folder)
        } else {
            EmptyState(icon: "folder", title: L("Ce dossier n'existe plus."))
        }
    }

    private func content(_ folder: VirtualFolder) -> some View {
        let items = VideoFolder.episodeOrder(store.items(folder, in: model.tracks))
        let videos = items.filter { $0.isVideo }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if items.isEmpty {
                    VStack(spacing: 14) {
                        EmptyState(icon: "folder.badge.plus", title: L("Aucun élément"),
                                   subtitle: L("Ajoutez des vidéos ou des musiques de la bibliothèque, ou des fichiers de l'app Fichiers."))
                        Button {
                            adding = true
                        } label: {
                            Label(L("Ajouter depuis la bibliothèque"), systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 50)
                    }
                    .padding(.top, 40)
                } else {
                    PlayShuffleButtons(tracks: items)
                        .padding(.horizontal, 16)
                    if grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], alignment: .leading, spacing: 18) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, track in
                                GeometryReader { geometry in
                                    Button {
                                        model.play(items, start: index)
                                    } label: {
                                        VideoTile(track: track, width: geometry.size.width)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        itemMenu(track, folder: folder)
                                    } preview: {
                                        if track.isVideo {
                                            VideoPreview(track: track)
                                        } else {
                                            TrackArtwork(track: track, width: 280, height: 280, radius: 0)
                                        }
                                    }
                                }
                                .frame(height: 150)
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, track in
                                TrackRow(track: track, onTap: { model.play(items, start: index) }) {
                                    itemMenu(track, folder: folder)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    Text(L("{count} élément(s)", ["count": "\(items.count)"]) + (videos.isEmpty ? "" : " · "
                         + L("{count} vidéo(s)", ["count": "\(videos.count)"])))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { grid.toggle() }
                } label: {
                    CircleIcon(systemName: grid ? "list.bullet" : "square.grid.2x2")
                }
                Button {
                    managing = true
                } label: {
                    CircleIcon(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog(folder.name, isPresented: $managing, titleVisibility: .visible) {
            VirtualFolderMenu(folder: folder, name: $name, renaming: $renaming, deleting: $removingFolder,
                              addingFrom: Binding(get: { nil }, set: { if $0 != nil { adding = true } }),
                              importingInto: $importingInto, importing: $importing)
        } message: {
            Text(L("Gérer le dossier virtuel"))
        }
        .alert(L("Renommer le dossier virtuel"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(L("Nom du dossier"), text: $name)
            Button(L("Annuler"), role: .cancel) { renaming = nil }
            Button(L("Renommer")) {
                store.rename(folder.id, to: name)
                renaming = nil
            }
        }
        .confirmationDialog(L("Supprimer « {name} » ?", ["name": folder.name]), isPresented: Binding(
            get: { removingFolder != nil }, set: { if !$0 { removingFolder = nil } }
        ), titleVisibility: .visible) {
            Button(L("Supprimer le dossier virtuel"), role: .destructive) {
                removingFolder = nil
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.delete(folder.id) }
            }
        } message: {
            Text(L("Les fichiers ne sont pas supprimés : ils restent dans la bibliothèque."))
        }
        .sheet(isPresented: $adding) {
            LibraryPicker(folder: folder)
                .environmentObject(model)
        }
        .virtualImporter(isPresented: $importing, folder: $importingInto)
        .trackSheets(picking: $picking, deleting: $deleting)
    }

    @ViewBuilder
    private func itemMenu(_ track: Track, folder: VirtualFolder) -> some View {
        Button(role: .destructive) {
            withAnimation { store.remove(track.path, from: folder.id) }
        } label: {
            Label(L("Retirer du dossier"), systemImage: "folder.badge.minus")
        }
        TrackActions(track: track, picking: $picking, deleting: $deleting)
    }
}

// MARK: - Choisir dans la bibliothèque

struct LibraryPicker: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @Environment(\.dismiss) private var dismiss
    let folder: VirtualFolder

    @State private var kind = "video"
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var candidates: [Track] {
        var list = model.tracks.filter { $0.exists }
        switch kind {
        case "video": list = list.filter { $0.isVideo }
        case "audio": list = list.filter { $0.isAudio }
        default: break
        }
        list.sort { $0.addedDate > $1.addedDate }
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return list }
        return list.filter { library.title($0).lowercased().contains(text) || $0.platformName.lowercased().contains(text) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $kind) {
                    Text(L("Vidéos")).tag("video")
                    Text(L("Musique")).tag("audio")
                    Text(L("Tout")).tag("all")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                List(candidates) { track in
                    let already = folder.paths.contains(track.path)
                    Button {
                        guard !already else { return }
                        if selected.contains(track.path) {
                            selected.remove(track.path)
                        } else {
                            selected.insert(track.path)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TrackArtwork(track: track, width: 64, height: 40, radius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(library.title(track))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(track.platformName.isEmpty ? Fmt.duration(library.duration(track))
                                     : track.platformName + " · " + Fmt.duration(library.duration(track)))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: already || selected.contains(track.path) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(already ? .secondary : .brand)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .searchable(text: $query, prompt: L("Rechercher"))
            .navigationTitle(L("Ajouter à « {name} »", ["name": folder.name]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? L("Ajouter") : L("Ajouter ({count})", ["count": "\(selected.count)"])) {
                        let ordered = candidates.map { $0.path }.filter { selected.contains($0) }
                        VirtualFolderStore.shared.add(ordered, to: folder.id)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

/// Sous-menu « Ajouter à un dossier virtuel » (menus des vidéos et morceaux).
struct AddToVirtualFolderMenu: View {
    @ObservedObject private var store = VirtualFolderStore.shared
    let track: Track

    var body: some View {
        Menu {
            if store.folders.isEmpty {
                Button {
                    let folder = store.create(L("Mes vidéos"))
                    store.add([track.path], to: folder.id)
                } label: {
                    Label(L("Nouveau dossier « Mes vidéos »"), systemImage: "folder.badge.plus")
                }
            }
            ForEach(store.folders) { folder in
                Button {
                    if store.contains(track.path, in: folder.id) {
                        store.remove(track.path, from: folder.id)
                    } else {
                        store.add([track.path], to: folder.id)
                    }
                } label: {
                    if store.contains(track.path, in: folder.id) {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
        } label: {
            Label(L("Dossier virtuel"), systemImage: "folder.badge.plus")
        }
    }
}
