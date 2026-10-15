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
                .tint(.brand)
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

    private var activeCount: Int {
        jobStore.jobs.filter { $0.active }.count
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
