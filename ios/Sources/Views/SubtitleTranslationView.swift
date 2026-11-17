import SwiftUI
import Translation

/// Traduit un fichier de sous-titres local en conservant les timecodes.
@available(iOS 18.0, *)
struct SubtitleTranslationView: View {
    let sourceURL: URL
    let onComplete: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceLanguage = "en"
    @State private var targetLanguage = "fr"
    @State private var configuration: TranslationSession.Configuration?
    @State private var translating = false
    @State private var errorMessage: String?

    private let languages: [(String, String)] = [
        ("en", "English"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"),
        ("it", "Italiano"), ("pt", "Português"), ("ru", "Русский"), ("ar", "العربية"),
        ("ja", "日本語"), ("zh-Hans", "中文"), ("ko", "한국어"), ("nl", "Nederlands")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Langues") {
                    Picker("Langue des sous-titres", selection: $sourceLanguage) {
                        ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Traduire en", selection: $targetLanguage) {
                        ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section {
                    Text("La traduction s’effectue sur cet iPhone. Le fichier traduit garde les horaires et sera ajouté au lecteur.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if translating {
                        ProgressView("Traduction en cours…")
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        guard sourceLanguage != targetLanguage else {
                            errorMessage = "Choisissez deux langues différentes."
                            return
                        }
                        errorMessage = nil
                        translating = true
                        configuration = TranslationSession.Configuration(
                            source: Locale.Language(identifier: sourceLanguage),
                            target: Locale.Language(identifier: targetLanguage)
                        )
                    } label: {
                        Label("Traduire les sous-titres", systemImage: "sparkles")
                    }
                    .disabled(translating)
                }
            }
            .navigationTitle("Traduction IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.disabled(translating)
                }
            }
        }
        .translationTask(configuration) { session in
            guard translating else { return }
            do {
                let translatedURL = try await translateFile(using: session)
                await MainActor.run { onComplete(translatedURL) }
                dismiss()
            } catch {
                await MainActor.run {
                    translating = false
                    configuration = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func translateFile(using session: TranslationSession) async throws -> URL {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        let input = try String(contentsOf: sourceURL, encoding: .utf8).replacingOccurrences(of: "\u{FEFF}", with: "")
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
            .map { $0.components(separatedBy: "\n") }
            .filter { !$0.isEmpty }

        var output: [String] = []
        var cueNumber = 1
        for lines in blocks {
            if lines.first?.uppercased().hasPrefix("WEBVTT") == true { continue }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let textLines = Array(lines.dropFirst(timeIndex + 1))
            guard !textLines.isEmpty else { continue }
            let sourceText = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await session.translate(sourceText)
            output.append("\(cueNumber)\n\(lines[timeIndex])\n\(response.targetText)")
            cueNumber += 1
        }
        guard !output.isEmpty else { throw TranslationFileError.noCues }
        let fileName = sourceURL.deletingPathExtension().lastPathComponent + ".\(targetLanguage).srt"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Faxel-\(UUID().uuidString)-\(fileName)")
        try (output.joined(separator: "\n\n") + "\n").write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }
}

private enum TranslationFileError: LocalizedError {
    case noCues
    var errorDescription: String? { "Aucun sous-titre exploitable n’a été trouvé." }
}
