import PhotosUI
import SwiftUI

/// Changer la pochette d'un morceau ou d'une vidéo avec une photo de l'iPhone.
final class CoverEditor: ObservableObject {
    static let shared = CoverEditor()
    static let changed = Notification.Name("FaxelCoverChanged")

    /// Le morceau dont on choisit la nouvelle pochette (ouvre la photothèque).
    @Published var track: Track?

    func apply(_ image: UIImage, to track: Track) {
        MediaLibrary.shared.setCustomCover(image, for: track)
        NotificationCenter.default.post(name: CoverEditor.changed, object: track.path)
    }

    func reset(_ track: Track) {
        MediaLibrary.shared.removeCustomCover(for: track)
        NotificationCenter.default.post(name: CoverEditor.changed, object: track.path)
    }
}

/// Affiche la photothèque quand une pochette est à changer.
struct CoverEditorPresenter: ViewModifier {
    @ObservedObject private var editor = CoverEditor.shared

    func body(content: Content) -> some View {
        content.sheet(item: $editor.track) { track in
            PhotoPicker { image in
                editor.track = nil
                if let image = image {
                    editor.apply(image, to: track)
                }
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func coverEditor() -> some View {
        modifier(CoverEditorPresenter())
    }
}

/// Boutons « Changer la pochette » / « Retirer la photo » pour les menus.
struct CoverMenuItems: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track

    var body: some View {
        Button {
            CoverEditor.shared.track = track
        } label: {
            Label(library.hasCustomCover(track) ? L("Changer la pochette…") : L("Ajouter une photo en pochette…"),
                  systemImage: "photo.badge.plus")
        }
        if library.hasCustomCover(track) {
            Button(role: .destructive) {
                CoverEditor.shared.reset(track)
            } label: {
                Label(L("Retirer la photo de pochette"), systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// Choix d'une photo (PHPicker : stable même si l'écran se redessine).
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            let done = onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                DispatchQueue.main.async { done(image) }
            }
        }
    }
}
