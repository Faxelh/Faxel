import SwiftUI

/// Onglet Télécharger : coller un ou plusieurs liens (YouTube, TikTok,
/// Instagram, Facebook, X…), analyser, choisir Vidéo / Audio et la qualité,
/// lancer ; puis suivre la file des téléchargements.
struct DownloadView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    oneTapButton
                    linkField
                    HStack(spacing: 8) {
                        actionButton(L("Coller"), icon: "doc.on.clipboard") {
                            editing = false
                            model.pasteLinks()
                        }
                        actionButton(L("Analyser"), icon: "sparkle.magnifyingglass") {
                            editing = false
                            model.analyzeLinks()
                        }
                        .disabled(model.analyzing)
                        actionButton(L("Effacer"), icon: "xmark.circle", tint: .secondary) {
                            editing = false
                            model.clearLinks()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)

                    header(L("Format"))
                    Picker("", selection: $model.media) {
                        Text(L("Vidéo")).tag("video")
                        Text(L("Audio")).tag("audio")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)

                    if model.media == "video" {
                        header(L("Qualité"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.qualities, id: \.self) { item in
                                    Button {
                                        model.quality = item
                                    } label: {
                                        Text(qualityLabel(item))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(model.quality == item ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .frame(height: 34)
                                            .background(Capsule().fill(model.quality == item ? Color.brand
                                                                       : Color(.tertiarySystemFill)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 18)
                    }

                    if let message = model.analysisMessage {
                        HStack(alignment: .top, spacing: 8) {
                            if model.analyzing {
                                ProgressView()
                            } else {
                                Image(systemName: model.analysisIsError ? "exclamationmark.triangle.fill" : "info.circle")
                                    .foregroundColor(model.analysisIsError ? .orange : .secondary)
                            }
                            Text(message)
                                .font(.system(size: 14))
                                .foregroundColor(model.analysisIsError ? .primary : .secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                    }

                    if let info = model.analysis {
                        resultCard(info)
                    }

                    Button {
                        editing = false
                        model.startDownload()
                    } label: {
                        Label(model.startTitle, systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)

                    if let info = model.analysis, !info.playlistURL.isEmpty {
                        Button {
                            model.downloadPlaylist(info.playlistURL, media: model.media, quality: model.quality)
                        } label: {
                            Label(L("Télécharger toute la playlist"), systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    if let info = model.analysis, info.kind == "playlist", !info.entries.isEmpty {
                        Button {
                            model.startAll()
                        } label: {
                            Text(L("Tout télécharger ({count})", ["count": "\(info.entries.count)"]))
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    HStack(spacing: 12) {
                        Tile(icon: "safari.fill", title: L("Navigateur")) {
                            model.showBrowser = true
                        }
                        Tile(icon: "magnifyingglass", title: "YouTube", tint: .red) {
                            model.showSearch = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)

                    Text(L("Dans TikTok, YouTube, Instagram… touchez « Partager » puis « Copier le lien », revenez ici et touchez « Coller ». Ou ouvrez la vidéo dans le Navigateur."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    JobsSection(store: model.jobStore)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DownloadAuroraBackground())
            .navigationTitle(L("Télécharger"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("OK")) { editing = false }
                }
            }
        }
    }

    /// Un seul geste : colle le lien du presse-papiers et lance le téléchargement aussitôt.
    private var oneTapButton: some View {
        Button {
            editing = false
            model.pasteAndDownload()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Télécharger en un geste"))
                        .font(.system(size: 16, weight: .bold))
                    Text(L("Colle le lien copié et lance le téléchargement"))
                        .font(.system(size: 12))
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.brand, .brand.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.brand.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    private var linkField: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.linkText)
                .focused($editing)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(8)
            if model.linkText.isEmpty {
                Text(L("Collez ici un lien (ou plusieurs, un par ligne)"))
                    .font(.system(size: 15))
                    .foregroundColor(Color(.placeholderText))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
            .padding(.bottom, 7)
    }

    private func actionButton(_ title: String, icon: String, tint: Color = .brand,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private func resultCard(_ info: Analysis) -> some View {
        HStack(spacing: 12) {
            Artwork(url: info.thumbnail, seed: info.url,
                    icon: info.kind == "photo" ? "photo.on.rectangle.angled"
                        : (info.kind == "playlist" ? "list.bullet.rectangle" : "play.rectangle.fill"),
                    width: 104, height: 66, radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                Text(info.details)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

/// Liste des téléchargements (seule partie redessinée pendant un téléchargement).
struct JobsSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: JobStore

    private var summary: String {
        let active = store.jobs.filter { $0.active }.count
        let done = store.jobs.filter { $0.isDone }.count
        let failed = store.jobs.filter { $0.isFailed }.count
        return L("{active} en cours · {done} terminé(s) · {failed} échec(s)",
                 ["active": "\(active)", "done": "\(done)", "failed": "\(failed)"])
    }

    var body: some View {
        if !store.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("Téléchargements"))
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                    Menu {
                        Button {
                            model.jobAction("pause_all")
                        } label: {
                            Label(L("Tout mettre en pause"), systemImage: "pause")
                        }
                        Button {
                            model.jobAction("resume_all")
                        } label: {
                            Label(L("Tout reprendre"), systemImage: "play")
                        }
                        Button(role: .destructive) {
                            model.jobAction("clear_finished")
                        } label: {
                            Label(L("Effacer les terminés"), systemImage: "trash")
                        }
                    } label: {
                        CircleIcon(systemName: "ellipsis")
                    }
                }
                .padding(.horizontal, 16)
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                LazyVStack(spacing: 10) {
                    ForEach(store.jobs) { job in
                        JobCard(job: job)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .id("jobs")
        }
    }
}

/// Fond doux et animé pour l'onglet Télécharger (dégradé qui dérive lentement).
struct DownloadAuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvasContext, size in
                let colors: [(Color, CGFloat, CGFloat)] = [
                    (.brand.opacity(0.22), 0.5 + 0.3 * CGFloat(sin(t * 0.07)), 0.15 + 0.2 * CGFloat(cos(t * 0.05))),
                    (.purple.opacity(0.16), 0.2 + 0.2 * CGFloat(cos(t * 0.06)), 0.6 + 0.25 * CGFloat(sin(t * 0.08))),
                    (.blue.opacity(0.14), 0.8 + 0.15 * CGFloat(sin(t * 0.09)), 0.75 + 0.2 * CGFloat(cos(t * 0.04))),
                ]
                for (color, fx, fy) in colors {
                    let center = CGPoint(x: size.width * fx, y: size.height * fy)
                    let radius = size.width * 0.55
                    let gradient = Gradient(colors: [color, color.opacity(0)])
                    canvasContext.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                    )
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}
