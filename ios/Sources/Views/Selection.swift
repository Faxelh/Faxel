import Photos
import SwiftUI
import UIKit

/// Sélection de plusieurs éléments (vidéos, sons) pour les exporter ou les supprimer d'un coup.
final class SelectionModel: ObservableObject {
    @Published var active = false
    @Published var ids: Set<String> = []

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func start(with id: String? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            active = true
            if let id = id { ids = [id] }
        }
    }

    func finish() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            active = false
            ids = []
        }
    }
}

/// Rond coché en haut d'une vignette ou au début d'une ligne.
struct SelectionCheck: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.brand : Color.black.opacity(0.35))
            Circle()
                .stroke(Color.white, lineWidth: 2)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.3), radius: 3)
    }
}

/// Barre du bas en mode sélection : tout sélectionner, Galerie, Fichiers, Partager, Supprimer.
struct SelectionBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var selection: SelectionModel
    /// Tous les éléments affichés (pour « Tout sélectionner »).
    let all: [Track]
    @State private var exportURLs: [URL]?
    @State private var shareURLs: [URL]?
    @State private var confirmDelete = false

    private var chosen: [Track] { all.filter { selection.ids.contains($0.id) } }

    private var allSelected: Bool { !all.isEmpty && selection.ids.count >= all.count }

    var body: some View {
        let picked = chosen
        let canPhotos = picked.contains { !$0.isAudio }
        VStack(spacing: 10) {
            HStack {
                Button(allSelected ? L("Tout désélectionner") : L("Tout sélectionner")) {
                    selection.ids = allSelected ? [] : Set(all.map { $0.id })
                }
                .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(L("{count} sélectionné(s)", ["count": "\(picked.count)"]))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 0) {
                action(L("Galerie"), "photo.on.rectangle.angled", enabled: canPhotos) {
                    model.saveManyToPhotos(picked)
                    selection.finish()
                }
                action(L("Fichiers"), "folder", enabled: !picked.isEmpty) {
                    exportURLs = Self.urls(picked)
                }
                action(L("Partager"), "square.and.arrow.up", enabled: !picked.isEmpty) {
                    shareURLs = Self.urls(picked)
                }
                action(L("Supprimer"), "trash", enabled: !picked.isEmpty, destructive: true) {
                    confirmDelete = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: Binding(get: { exportURLs != nil }, set: { if !$0 { exportURLs = nil } })) {
            FilesExporter(urls: exportURLs ?? []) { saved in
                exportURLs = nil
                if saved {
                    model.show(L("{count} élément(s) enregistré(s) dans Fichiers.", ["count": "\(picked.count)"]), .ok)
                    selection.finish()
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
            ShareSheet(items: shareURLs ?? [])
                .ignoresSafeArea()
        }
        .confirmationDialog(L("Supprimer {count} élément(s) ?", ["count": "\(picked.count)"]),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Supprimer les fichiers"), role: .destructive) {
                model.deleteMany(picked)
                selection.finish()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Les fichiers seront effacés de l'iPhone."))
        }
    }

    static func urls(_ tracks: [Track]) -> [URL] {
        tracks.flatMap { track -> [URL] in
            if track.isFolder { return track.photoURLs }
            return FileManager.default.fileExists(atPath: track.path) ? [track.fileURL] : []
        }
    }

    private func action(_ title: String, _ icon: String, enabled: Bool, destructive: Bool = false,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(enabled ? (destructive ? Color.red : Color.primary) : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
    }
}

/// « Enregistrer dans Fichiers » : l'utilisateur choisit le dossier (iCloud Drive, Sur mon iPhone…).
struct FilesExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: (Bool) -> Void

        init(done: @escaping (Bool) -> Void) {
            self.done = done
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            done(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            done(false)
        }
    }
}

/// Feuille de partage d'iOS (AirDrop, WhatsApp, Enregistrer…) pour plusieurs fichiers.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Bouton « Sélectionner » / « OK » de la barre du haut.
struct SelectButton: View {
    @ObservedObject var selection: SelectionModel

    var body: some View {
        Button {
            if selection.active { selection.finish() } else { selection.start() }
        } label: {
            Text(selection.active ? L("OK") : L("Sélectionner"))
                .font(.system(size: 15, weight: .semibold))
        }
    }
}
