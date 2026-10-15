import SwiftUI

/// Onglet Réglages, organisé comme les Réglages d'iOS.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var browser: BrowserModel
    @AppStorage("language") private var language = "system"
    @AppStorage("theme") private var theme = "system"
    @AppStorage("maxParallel") private var maxParallel = 2
    @AppStorage("defaultMedia") private var defaultMedia = "video"
    @AppStorage("defaultQuality") private var defaultQuality = "Meilleure"
    @AppStorage("saveToPhotos") private var saveToPhotos = true
    @AppStorage("skipDuplicates") private var skipDuplicates = true
    @AppStorage("cleanTitles") private var cleanTitles = true
    @AppStorage("autoRetry") private var autoRetry = true
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("homePage") private var homePage = "https://www.tiktok.com/"
    @AppStorage("useCookies") private var useCookies = true
    @AppStorage("appLock") private var appLock = false
    @AppStorage("openPlayer") private var openPlayer = false
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("autoSubtitles") private var autoSubtitles = true
    @AppStorage("autoNextVideo") private var autoNextVideo = true
    @AppStorage("askDownload") private var askDownload = true
    @AppStorage("allowAV1") private var allowAV1 = true
    @AppStorage("subtitleSize") private var subtitleSize = 2
    @State private var storage = ""
    @State private var confirmRestore = false
    @State private var importing = false
    @State private var showWifi = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        model.showSearch = true
                    } label: {
                        SettingsLabel(title: L("Rechercher (bibliothèque et YouTube)"), icon: "magnifyingglass",
                                      color: .brand)
                    }
                    .foregroundColor(.primary)
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { model.showBrowser = true }
                    } label: {
                        SettingsLabel(title: L("Navigateur"), icon: "safari.fill", color: .blue)
                    }
                    .foregroundColor(.primary)
                }

                Section {
                    Picker(selection: $language) {
                        Text(L("Langue du téléphone")).tag("system")
                        ForEach(Lang.supported, id: \.self) { code in
                            Text(Lang.name(code)).tag(code)
                        }
                    } label: {
                        SettingsLabel(title: L("Langue"), icon: "globe", color: .blue)
                    }
                    .pickerStyle(.navigationLink)
                    Picker(selection: $theme) {
                        Text(L("Automatique (système)")).tag("system")
                        Text(L("Clair")).tag("light")
                        Text(L("Sombre")).tag("dark")
                    } label: {
                        SettingsLabel(title: L("Thème"), icon: "moon.fill", color: .indigo)
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text(L("Général"))
                }

                Section {
                    Toggle(isOn: $openPlayer) {
                        SettingsLabel(title: L("Ouvrir le lecteur en plein écran"), icon: "music.note", color: .pink)
                    }
                    Toggle(isOn: $autoLandscape) {
                        SettingsLabel(title: L("Vidéos horizontales en paysage"), icon: "rectangle.landscape.rotate",
                                      color: .orange)
                    }
                    Toggle(isOn: $autoSubtitles) {
                        SettingsLabel(title: L("Sous-titres automatiques"), icon: "captions.bubble.fill", color: .blue)
                    }
                    Picker(selection: $subtitleSize) {
                        Text(L("Petit")).tag(1)
                        Text(L("Moyen")).tag(2)
                        Text(L("Grand")).tag(3)
                        Text(L("Très grand")).tag(4)
                    } label: {
                        SettingsLabel(title: L("Taille des sous-titres"), icon: "textformat.size", color: .indigo)
                    }
                    Toggle(isOn: $autoNextVideo) {
                        SettingsLabel(title: L("Enchaîner les vidéos"), icon: "forward.end.fill", color: .green)
                    }
                } header: {
                    Text(L("Lecture"))
                } footer: {
                    Text(L("Les sous-titres .srt ou .vtt portant le même nom que la vidéo (ex. Film.mp4 et Film.srt) sont chargés automatiquement."))
                }

                Section {
                    Button {
                        importing = true
                    } label: {
                        SettingsLabel(title: L("Importer depuis Fichiers"), icon: "square.and.arrow.down.fill", color: .brand)
                    }
                    .foregroundColor(.primary)
                    Button {
                        showWifi = true
                    } label: {
                        SettingsLabel(title: L("Transfert Wi-Fi depuis l'ordinateur"), icon: "wifi", color: .blue)
                    }
                    .foregroundColor(.primary)
                    Button {
                        model.rescan(force: true)
                    } label: {
                        SettingsLabel(title: L("Actualiser la bibliothèque"), icon: "arrow.clockwise", color: .green)
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(L("Bibliothèque"))
                } footer: {
                    Text(L("« Importer depuis Fichiers » : choisissez un ou plusieurs fichiers, ou un dossier entier (avec ses sous-dossiers) à copier dans Faxel. Avec 3uTools : Apps › Faxel › Documents (partage de fichiers), puis glissez vos musiques et vidéos. Faxel les affiche à la prochaine ouverture ou en tirant vers le bas."))
                }

                Section {
                    Picker(selection: $maxParallel) {
                        ForEach(1...3, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    } label: {
                        SettingsLabel(title: L("Simultanés"), icon: "square.stack.3d.down.right.fill", color: .brand)
                    }
                    if DeviceCodecs.av1Supported {
                        Toggle(isOn: $allowAV1) {
                            SettingsLabel(title: L("Vidéos 2K / 4K (AV1)"), icon: "sparkles.tv.fill", color: .orange)
                        }
                    }
                    Picker(selection: $defaultMedia) {
                        Text(L("Vidéo (MP4)")).tag("video")
                        Text(L("Audio (M4A)")).tag("audio")
                    } label: {
                        SettingsLabel(title: L("Type par défaut"), icon: "film.fill", color: .purple)
                    }
                    .pickerStyle(.navigationLink)
                    Picker(selection: $defaultQuality) {
                        ForEach(standardQualities, id: \.self) { item in
                            Text(qualityLabel(item)).tag(item)
                        }
                    } label: {
                        SettingsLabel(title: L("Qualité par défaut"), icon: "sparkles.tv.fill", color: .teal)
                    }
                    .pickerStyle(.navigationLink)
                    Toggle(isOn: $saveToPhotos) {
                        SettingsLabel(title: L("Ajouter à l'app Photos"), icon: "photo.fill", color: .pink)
                    }
                    Toggle(isOn: $skipDuplicates) {
                        SettingsLabel(title: L("Ignorer les doublons"), icon: "doc.on.doc.fill", color: .gray)
                    }
                    Toggle(isOn: $cleanTitles) {
                        SettingsLabel(title: L("Noms de fichiers propres"), icon: "textformat", color: .blue)
                    }
                    Toggle(isOn: $autoRetry) {
                        SettingsLabel(title: L("Nouvelles tentatives"), icon: "arrow.clockwise", color: .green)
                    }
                    Toggle(isOn: $keepAwake) {
                        SettingsLabel(title: L("Écran toujours allumé"), icon: "sun.max.fill", color: .orange)
                    }
                } header: {
                    Text(L("Téléchargements"))
                }

                Section {
                    Picker(selection: $homePage) {
                        ForEach(browserSites) { site in
                            Text(site.name).tag(site.link)
                        }
                    } label: {
                        SettingsLabel(title: L("Page d'accueil"), icon: "safari.fill", color: .blue)
                    }
                    .pickerStyle(.navigationLink)
                    Toggle(isOn: $askDownload) {
                        SettingsLabel(title: L("Proposer de télécharger les vidéos lues"), icon: "arrow.down.app.fill",
                                      color: .brand)
                    }
                    Toggle(isOn: $useCookies) {
                        SettingsLabel(title: L("Utiliser mes connexions"), icon: "person.crop.circle.badge.checkmark",
                                      color: .green)
                    }
                    Button {
                        model.showBrowser = true
                    } label: {
                        SettingsLabel(title: L("Ouvrir le navigateur"), icon: "safari", color: .blue)
                    }
                    .foregroundColor(.primary)
                    Button {
                        model.forgetCookies()
                    } label: {
                        SettingsLabel(title: L("Oublier les connexions"), icon: "person.crop.circle.badge.xmark",
                                      color: .red)
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(L("Navigateur"))
                } footer: {
                    Text(L("Connectez-vous à vos comptes dans le Navigateur : Faxel réutilise ces connexions pour les contenus réservés aux abonnés."))
                }

                Section {
                    Toggle(isOn: $appLock) {
                        SettingsLabel(title: L("Verrouiller Faxel à l'ouverture"), icon: "faceid", color: .green)
                    }
                    Button {
                        model.openVault()
                    } label: {
                        HStack {
                            SettingsLabel(title: L("Coffre"), icon: "lock.fill", color: .red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(L("Confidentialité"))
                } footer: {
                    Text(L("Faxel demandera Face ID à chaque ouverture. Le Coffre est toujours protégé, même si cette option est désactivée."))
                }

                Section {
                    Button {
                        model.openInFiles()
                    } label: {
                        SettingsLabel(title: L("Ouvrir dans Fichiers"), icon: "folder.fill", color: .blue)
                    }
                    .foregroundColor(.primary)
                    Button {
                        model.backup()
                    } label: {
                        SettingsLabel(title: L("Sauvegarder"), icon: "externaldrive.fill", color: .gray)
                    }
                    .foregroundColor(.primary)
                    Button {
                        confirmRestore = true
                    } label: {
                        SettingsLabel(title: L("Restaurer"), icon: "arrow.counterclockwise", color: .gray)
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(L("Stockage"))
                } footer: {
                    Text(storage)
                }

                Section {
                    ShareLink(item: L("J'utilise Faxel pour garder mes vidéos et musiques hors ligne. Essayez-la !")) {
                        SettingsLabel(title: L("Partager Faxel"), icon: "square.and.arrow.up", color: .brand)
                    }
                    .foregroundColor(.primary)
                    if let mail = URL(string: "mailto:kwadioh@gmail.com?subject=Faxel") {
                        Link(destination: mail) {
                            SettingsLabel(title: L("Envoyer un avis"), icon: "envelope.fill", color: .blue)
                        }
                        .foregroundColor(.primary)
                    }
                    NavigationLink {
                        AppNameView()
                    } label: {
                        SettingsLabel(title: L("Nom de l'application"), icon: "character.cursor.ibeam", color: .purple)
                    }
                    NavigationLink {
                        UpdatesView()
                    } label: {
                        SettingsLabel(title: L("Mises à jour"), icon: "arrow.down.circle.fill", color: .green)
                    }
                    NavigationLink {
                        AudioLogView()
                    } label: {
                        SettingsLabel(title: L("Journal du lecteur"), icon: "list.bullet.rectangle", color: .gray)
                    }
                    NavigationLink {
                        HelpView()
                    } label: {
                        SettingsLabel(title: L("Aide"), icon: "questionmark.circle.fill", color: .orange)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsLabel(title: L("À propos"), icon: "info.circle.fill", color: .gray)
                    }
                } footer: {
                    Text(L("Faxel télécharge uniquement les contenus publics, ou ceux auxquels vous avez légitimement accès. Respectez le droit d'auteur et les règles des plateformes."))
                }
            }
            .navigationTitle(L("Réglages"))
            .onAppear {
                DispatchQueue.global(qos: .utility).async {
                    let text = model.storageText()
                    DispatchQueue.main.async { storage = text }
                }
            }
            .onChange(of: maxParallel) { _ in model.applyEngineSettings() }
            .onChange(of: skipDuplicates) { _ in model.applyEngineSettings() }
            .onChange(of: cleanTitles) { _ in model.applyEngineSettings() }
            .onChange(of: autoRetry) { _ in model.applyEngineSettings() }
            .onChange(of: allowAV1) { _ in model.applyEngineSettings() }
            .onChange(of: useCookies) { enabled in
                model.applyEngineSettings()
                if enabled { browser.exportCookies() }
            }
            .onChange(of: defaultMedia) { value in model.media = value }
            .onChange(of: defaultQuality) { value in
                if model.analysis == nil { model.quality = value }
            }
            .onChange(of: homePage) { link in
                browser.load(link)
                model.showBrowser = true
                model.show(L("Connectez-vous à votre compte si besoin : Faxel réutilisera cette connexion pour télécharger."),
                           .info)
            }
            .importer(isPresented: $importing)
            .sheet(isPresented: $showWifi) {
                WifiTransferView()
                    .environmentObject(model)
            }
            .confirmationDialog(L("Restaurer la sauvegarde ?"), isPresented: $confirmRestore, titleVisibility: .visible) {
                Button(L("Restaurer")) { model.restore() }
                Button(L("Annuler"), role: .cancel) {}
            } message: {
                Text(L("La bibliothèque et les playlists actuelles seront remplacées par celles de la sauvegarde."))
            }
        }
    }
}

struct HelpItem: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

struct HelpView: View {
    private let items: [HelpItem] = [
        HelpItem(question: "Comment ajouter ma musique avec 3uTools ?",
                 answer: "Branchez l'iPhone, ouvrez 3uTools › Apps, choisissez Faxel puis « Documents » (partage de fichiers), et glissez vos fichiers MP3, M4A, FLAC, WAV, MP4, MOV… Rouvrez Faxel : ils apparaissent dans la Bibliothèque. iTunes et le Finder du Mac fonctionnent de la même façon."),
        HelpItem(question: "Comment ajouter des fichiers depuis l'iPhone ?",
                 answer: "Dans l'app Fichiers, copiez-les dans « Sur mon iPhone › Faxel », ou touchez « Importer » dans Faxel. Depuis une autre app, utilisez « Partager › Ouvrir avec Faxel »."),
        HelpItem(question: "Comment télécharger une vidéo ou une musique ?",
                 answer: "Dans TikTok, YouTube, Instagram, Facebook…, touchez « Partager » puis « Copier le lien ». Dans Faxel, onglet Télécharger, touchez « Coller », choisissez Vidéo ou Audio. Vous pouvez aussi chercher un titre dans l'onglet Rechercher › YouTube."),
        HelpItem(question: "Comment afficher des sous-titres ?",
                 answer: "Placez le fichier .srt ou .vtt à côté de la vidéo avec le même nom (Film.mp4 et Film.srt) : il est chargé tout seul. Sinon, dans le lecteur, touchez la bulle de sous-titres puis « Charger un fichier ». Les sous-titres intégrés à la vidéo apparaissent aussi dans ce menu."),
        HelpItem(question: "Comment regarder en paysage ?",
                 answer: "Les vidéos horizontales passent en paysage automatiquement. Touchez « Pivoter » pour changer, et le cadenas pour bloquer la rotation. Pincez l'image pour remplir l'écran, double-touchez à droite ou à gauche pour avancer ou reculer de 10 s, glissez à gauche pour la luminosité et à droite pour le volume."),
        HelpItem(question: "Comment cacher un fichier ?",
                 answer: "Touchez ⋯ puis « Mettre au Coffre ». Il n'apparaît plus que dans le Coffre, protégé par Face ID."),
        HelpItem(question: "Pourquoi un téléchargement échoue ?",
                 answer: "Le contenu est peut-être privé, supprimé, en direct ou protégé (DRM). Pour un contenu réservé aux abonnés, connectez-vous dans le Navigateur puis réessayez."),
    ]

    var body: some View {
        List {
            ForEach(items) { item in
                DisclosureGroup {
                    Text(L(item.answer))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } label: {
                    Text(L(item.question))
                        .font(.system(size: 16, weight: .medium))
                }
                .tint(.brand)
            }
        }
        .navigationTitle(L("Aide"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
    }

    private var engineText: String {
        if model.engineReady { return "Python " + (model.engineInfo["python"] ?? "") }
        return model.engineError == nil ? L("Démarrage…") : L("Erreur")
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    Text("Faxel")
                        .font(.system(size: 30, weight: .bold))
                    Text(L("Version {version}", ["version": version]))
                        .foregroundColor(.secondary)
                    Text(L("Votre musique et vos vidéos, partout, hors ligne."))
                        .font(.system(size: 16))
                    Text(L("par Faxel"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent(L("Moteur"), value: engineText)
                LabeledContent("yt-dlp", value: model.engineInfo["ytdlp"] ?? "—")
                LabeledContent(L("JavaScript (YouTube)"), value: model.engineInfo["javascript"] == "1" ? "JavaScriptCore" : "—")
            } header: {
                Text(L("Moteur de téléchargement"))
            } footer: {
                if let error = model.engineError {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(L("À propos"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
