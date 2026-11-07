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
    @AppStorage("faxelProfilePhotoPath") private var profilePhotoPath = ""

    private var activeCount: Int {
        jobStore.jobs.filter { $0.active }.count
    }

    private var failedCount: Int {
        jobStore.jobs.filter(\.isFailed).count
    }

    /// L'onglet Navigateur ne change pas d'écran : il fait glisser le navigateur depuis la droite.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { model.tab },
            set: { newTab in
                if newTab == .browser {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { model.showBrowser = true }
                } else {
                    model.tab = newTab
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView()
                .safeAreaInset(edge: .bottom) { MiniPlayer { model.showNowPlaying = true } }
                .tabItem { Label(L("Accueil"), systemImage: "house.fill") }
                .tag(AppTab.home)
            LibraryView()
                .safeAreaInset(edge: .bottom) { MiniPlayer { model.showNowPlaying = true } }
                .tabItem { Label(L("Bibliothèque"), systemImage: "square.stack.fill") }
                .tag(AppTab.library)
            DownloadView()
                .safeAreaInset(edge: .bottom) { MiniPlayer { model.showNowPlaying = true } }
                .tabItem { Label(L("Télécharger"), systemImage: "arrow.down.circle.fill") }
                .badge(activeCount)
                .tag(AppTab.download)
            SettingsView()
                .safeAreaInset(edge: .bottom) { MiniPlayer { model.showNowPlaying = true } }
                .tabItem { Label(L("Réglages"), systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
            Color.clear
                .tabItem { Label(L("Navigateur"), systemImage: "globe") }
                .tag(AppTab.browser)
        }
        .toolbar(.hidden, for: .tabBar)
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

    private var faxelDock: some View {
        HStack(spacing: 3) {
            homeDockButton
            libraryDockButton
            downloadDockButton
            browserDockButton
            queueDockButton
            profileDockButton
        }
        .padding(7)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.top, 5)
        .padding(.bottom, 7)
        .background(LinearGradient(colors: [Color.clear, Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }

    private var homeDockButton: some View {
        dockButton("house.fill", label: L("Accueil"), selected: model.tab == .home) { model.tab = .home }
    }

    private var libraryDockButton: some View {
        dockButton("play.rectangle", label: L("Bibliothèque"), selected: model.tab == .library) { model.tab = .library }
    }

    private var downloadDockButton: some View {
        dockButton("storefront", label: L("Télécharger"), selected: model.tab == .download, badge: activeCount) { model.tab = .download }
    }

    private var browserDockButton: some View {
        dockButton("person.3", label: L("Navigateur"), selected: model.showBrowser) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { model.showBrowser = true }
        }
    }

    private var queueDockButton: some View {
        dockButton("bell", label: L("Téléchargements"), selected: showQueue, badge: failedCount) { showQueue = true }
    }

    private var profileDockButton: some View {
            Button {
                model.tab = .settings
            } label: {
                profileAvatar
                    .frame(width: 34, height: 34).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if model.tab == .settings { Capsule().fill(Color.white.opacity(0.12)) }
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
                .font(.system(size: 25, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    if selected { Capsule().fill(Color.white.opacity(0.12)) }
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
