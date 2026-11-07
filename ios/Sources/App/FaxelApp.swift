import SwiftUI

@main
struct FaxelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var player = AudioPlayer()
    @StateObject private var video = VideoPlayerModel()
    @StateObject private var browser = BrowserModel()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("language") private var language = "system"
    @AppStorage("faxelAccentHex") private var accentHex = "8B5CF6"
    @AppStorage("faxelProfilePhotoPath") private var profilePhotoPath = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SelfTest.runIfRequested()
    }

    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            let _ = Lang.apply(language)
            RootView()
                .environmentObject(model)
                .environmentObject(player)
                .environmentObject(video)
                .environmentObject(browser)
                .environmentObject(model.jobStore)
                .tint(Color.hex(accentHex))
                .preferredColorScheme(scheme)
                .id(language)
                .onAppear {
                    model.attach(player)
                    model.attach(video)
                }
                .onChange(of: scenePhase) { phase in
                    model.scenePhaseChanged(phase)
                    if phase == .background { browser.exportCookies() }
                }
                .onChange(of: language) { _ in
                    model.setEngineLanguage()
                }
                .onOpenURL { url in
                    model.handleOpenURL(url)
                }
                .updatePrompt()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var video: VideoPlayerModel
    @EnvironmentObject var browser: BrowserModel
    @EnvironmentObject var jobStore: JobStore
    @State private var showQueue = false
    @State private var showCompression = false
    @Namespace private var dockSelection
    @AppStorage("faxelProfilePhotoPath") private var profilePhotoPath = ""

    private var activeCount: Int {
        jobStore.jobs.filter { $0.active }.count
    }

    private var failedCount: Int {
        jobStore.jobs.filter(\.isFailed).count
    }

    var body: some View {
        mainTabs
        .safeAreaInset(edge: .bottom) { MiniPlayer { model.showNowPlaying = true } }
        .safeAreaInset(edge: .bottom, spacing: 0) { faxelDock }
        .overlay {
            if model.showBrowser {
                BrowserView()
                    .environmentObject(model)
                    .environmentObject(browser)
                    .environmentObject(jobStore)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: model.showBrowser)
        .overlay(alignment: .top) {
            if let toast = model.toast, model.videoSession == nil {
                ToastBanner(toast: toast)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .overlay {
            if model.appLocked {
                LockView()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $model.showNowPlaying) {
            NowPlayingView()
                .environmentObject(player)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showSearch) {
            SearchView()
                .environmentObject(model)
                .environmentObject(player)
                .environmentObject(video)
                .environmentObject(browser)
                .environmentObject(jobStore)
        }
        .sheet(isPresented: $showQueue) {
            DownloadQueueView()
                .environmentObject(model)
                .environmentObject(jobStore)
        }
        .sheet(isPresented: $showCompression) {
            CompressionView().environmentObject(model)
        }
        .fullScreenCover(item: $model.videoSession) { session in
            VideoPlayerView(session: session)
                .environmentObject(model)
                .environmentObject(player)
                .environmentObject(video)
        }
        .coverEditor()
        .watermarkEditor(model)
        .onChange(of: model.tab) { tab in
            if tab != .library {
                model.lockVault()
            }
        }
    }

    private var mainTabs: some View {
        ZStack {
            HomeView().opacity(model.tab == .home || model.tab == .browser ? 1 : 0)
                .allowsHitTesting(model.tab == .home || model.tab == .browser)
            LibraryView().opacity(model.tab == .library ? 1 : 0).allowsHitTesting(model.tab == .library)
            DownloadView().opacity(model.tab == .download ? 1 : 0).allowsHitTesting(model.tab == .download)
            SettingsView().opacity(model.tab == .settings ? 1 : 0).allowsHitTesting(model.tab == .settings)
        }
        .animation(.easeInOut(duration: 0.18), value: model.tab)
    }

    private var faxelDock: some View {
        HStack(spacing: 3) {
            homeDockButton
            libraryDockButton
            downloadDockButton
            compressionDockButton
            profileDockButton
            browserDockButton
        }
        .padding(5)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(LinearGradient(colors: [Color.clear, Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.tab)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: showCompression)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.showBrowser)
    }

    private var homeDockButton: some View {
        dockButton("house.fill", label: L("Accueil"), selected: model.tab == .home && !model.showBrowser && !showQueue && !showCompression) { model.tab = .home }
    }

    private var libraryDockButton: some View {
        dockButton("play.rectangle", label: L("Bibliothèque"), selected: model.tab == .library && !model.showBrowser && !showQueue && !showCompression) { model.tab = .library }
    }

    private var downloadDockButton: some View {
        dockButton("storefront", label: L("Télécharger"), selected: model.tab == .download && !model.showBrowser && !showQueue && !showCompression, badge: activeCount) { model.tab = .download }
    }

    private var browserDockButton: some View {
        dockButton("globe", label: L("Navigateur"), selected: model.showBrowser && !showQueue && !showCompression) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { model.showBrowser = true }
        }
    }

    private var queueDockButton: some View {
        dockButton("bell", label: L("Téléchargements"), selected: showQueue, badge: failedCount) { showQueue = true }
    }

    private var compressionDockButton: some View {
        dockButton("arrow.down.right.and.arrow.up.left", label: L("Compresser"), selected: showCompression) { showCompression = true }
    }

    private var profileDockButton: some View {
            Button {
                model.tab = .settings
            } label: {
                profileAvatar
                    .frame(width: 30, height: 30).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if model.tab == .settings && !model.showBrowser && !showQueue && !showCompression {
                            Capsule().fill(Color.white.opacity(0.12))
                                .matchedGeometryEffect(id: "faxelDockSelection", in: dockSelection)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Réglages"))
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if !profilePhotoPath.isEmpty, let image = UIImage(contentsOfFile: profilePhotoPath) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image("Logo").resizable().scaledToFill()
        }
    }

    private func dockButton(_ icon: String, label: String, selected: Bool, badge: Int = 0,
                            action: @escaping () -> Void) -> some View {
        return Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if selected {
                        Capsule().fill(Color.white.opacity(0.12))
                            .matchedGeometryEffect(id: "faxelDockSelection", in: dockSelection)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .offset(x: -2, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct DownloadQueueView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.jobs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bell").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text(L("Aucun téléchargement")).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                } else {
                    JobsSection(store: store)
                        .padding(.top, 12)
                }
            }
            .navigationTitle(L("Téléchargements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fermer")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Écran de verrouillage (Face ID à l'ouverture).
struct LockView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("Faxel")
                    .font(.system(size: 28, weight: .bold))
                Text(L("Faxel est verrouillée."))
                    .foregroundColor(.secondary)
                Button {
                    model.unlockApp()
                } label: {
                    Label(L("Déverrouiller"), systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 60)
                .padding(.top, 12)
                Spacer()
            }
        }
    }
}
