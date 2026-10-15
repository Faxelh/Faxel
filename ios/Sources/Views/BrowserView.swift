import SwiftUI
import WebKit

struct BrowserSite: Identifiable, Hashable {
    let name: String
    let link: String
    var id: String { name }
}

let browserSites: [BrowserSite] = [
    BrowserSite(name: "YouTube", link: "https://m.youtube.com/"),
    BrowserSite(name: "Facebook", link: "https://m.facebook.com/watch/"),
    BrowserSite(name: "Instagram", link: "https://www.instagram.com/"),
    BrowserSite(name: "X", link: "https://x.com/"),
]

/// Le lien ressemble-t-il à une vidéo (ou une publication) téléchargeable ?
func looksLikeVideo(_ link: String) -> Bool {
    let lower = link.lowercased()
    guard lower.hasPrefix("http") else { return false }
    let markers = ["/video/", "/photo/", "/reel/", "/reels/", "/videos/", "watch?v=", "/watch/", "youtu.be/",
                   "/shorts/", "/status/", "fb.watch", "/p/", "/tv/", "dailymotion.com/video", "vimeo.com/",
                   "/share/v/", "/share/r/", "story.php", "/playlist?list="]
    return markers.contains { lower.contains($0) }
}

/// Une page du navigateur (historique ou signet).
struct BrowserEntry: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var title: String
    var url: String
    var date = Date()
    var visits = 1

    var host: String {
        URL(string: url)?.host ?? url
    }
}

/// Un onglet du navigateur (comme dans Amerigo ou Safari).
final class BrowserTab: Identifiable {
    let id = UUID()
    let webView: WKWebView
    var snapshot: UIImage?
    /// Adresse à charger quand l'onglet sera affiché (onglets retrouvés au lancement).
    var pending: URL?

    init(webView: WKWebView, pending: URL? = nil) {
        self.webView = webView
        self.pending = pending
    }

    var title: String {
        let text = webView.title ?? ""
        if !text.isEmpty { return text }
        return webView.url?.host ?? pending?.host ?? L("Nouvel onglet")
    }

    var link: String {
        webView.url?.absoluteString ?? pending?.absoluteString ?? ""
    }
}

/// Navigateur intégré : onglets, signets, historique, sites les plus visités,
/// et transmission des connexions (cookies) au moteur pour les contenus réservés.
/// Relais sans cycle de mémoire entre la page et le navigateur.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var currentIndex = 0
    @Published var address = ""
    @Published private(set) var currentURL = ""
    @Published private(set) var pageTitle = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var loading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var history: [BrowserEntry] = BrowserModel.loadEntries("browserHistory")
    @Published private(set) var bookmarks: [BrowserEntry] = BrowserModel.loadEntries("browserBookmarks")
    /// Une vidéo vient de démarrer : on propose de la télécharger (comme Amerigo).
    @Published var mediaPrompt = false
    private var promptedKeys = Set<String>()
    private var promptWork: DispatchWorkItem?

    /// Prévient Faxel quand une vidéo se met à jouer dans la page.
    static let mediaWatch = """
    (function () {
      if (window.__faxelMedia) return; window.__faxelMedia = true;
      document.addEventListener('play', function (e) {
        var v = e.target;
        if (!v || v.tagName !== 'VIDEO') return;
        try {
          var r = v.getBoundingClientRect();
          if (r.width < 120 || r.height < 80) return;
          window.webkit.messageHandlers.faxelMedia.postMessage({
            src: String(v.currentSrc || v.src || ''), muted: !!v.muted,
            duration: isFinite(v.duration) ? v.duration : 0, page: location.href
          });
        } catch (err) {}
      }, true);
    })();
    """
    /// Signale si une vidéo joue dans la page (reels, YouTube…) : l'écran reste allumé.
    static let awakeWatch = """
    (function () {
      if (window.__faxelAwake) return; window.__faxelAwake = true;
      var id = Math.random().toString(36).slice(2), last = null;
      function videos(root, out) {
        var list = root.querySelectorAll('video');
        for (var i = 0; i < list.length; i++) out.push(list[i]);
        return out;
      }
      function playing() {
        var list = videos(document, []);
        for (var i = 0; i < list.length; i++) {
          var v = list[i];
          if (!v.paused && !v.ended && v.readyState >= 2) return true;
        }
        return false;
      }
      function send(now) {
        try { window.webkit.messageHandlers.faxelAwake.postMessage({ id: id, playing: now }); } catch (e) {}
      }
      // Vérifié toutes les 2 s (reels qui défilent, lecteurs qui démarrent sans événement),
      // et renvoyé à chaque fois pendant la lecture : l'app sait que la page est toujours là.
      function report() {
        var now = playing();
        if (now || now !== last) send(now);
        last = now;
      }
      ['play', 'playing', 'pause', 'ended', 'emptied', 'abort'].forEach(function (name) {
        document.addEventListener(name, function () { setTimeout(report, 50); }, true);
      });
      document.addEventListener('visibilitychange', report);
      window.addEventListener('pagehide', function () { last = false; send(false); });
      setInterval(report, 2000);
      report();
    })();
    """
    private var observations: [NSKeyValueObservation] = []
    private var exportWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?

    var webView: WKWebView {
        tabs[min(max(0, currentIndex), tabs.count - 1)].webView
    }

    var currentTab: BrowserTab {
        tabs[min(max(0, currentIndex), tabs.count - 1)]
    }

    static var homeLink: String {
        UserDefaults.standard.string(forKey: "homePage") ?? browserSites[0].link
    }
    static let touchFix = """
    (function () {
      try {
        if (document.getElementById('nyx-touch-fix')) return;
        var style = document.createElement('style');
        style.id = 'nyx-touch-fix';
        style.textContent = 'html, body, * { touch-action: pan-y !important; }';
        (document.head || document.documentElement).appendChild(style);
      } catch (e) {}
    })();
    """

    /// Retient les vidéos des fils (TikTok…) au fur et à mesure qu'ils se chargent,
    /// pour retrouver le lien exact de la vidéo affichée.
    static let feedHook = """
    (function () {
      if (window.__faxelHook) return; window.__faxelHook = true;
      window.__faxelItems = [];
      function keyOf(u) { try { var x = new URL(u, location.href); return x.host + x.pathname; } catch (e) { return ''; } }
      function collect(obj, depth) {
        if (!obj || typeof obj !== 'object' || depth > 9) return;
        if (Array.isArray(obj)) { for (var i = 0; i < obj.length; i++) collect(obj[i], depth + 1); return; }
        var id = obj.id || obj.aweme_id || obj.itemId;
        var video = obj.video;
        if (id && video && typeof video === 'object' && /^\\d{10,}$/.test(String(id))) {
          var keys = [];
          ['playAddr', 'downloadAddr', 'cover', 'originCover', 'dynamicCover'].forEach(function (k) {
            var u = video[k]; if (typeof u === 'string') keys.push(keyOf(u));
            if (u && u.url_list) u.url_list.forEach(function (x) { keys.push(keyOf(x)); });
          });
          if (video.PlayAddrStruct && video.PlayAddrStruct.UrlList) video.PlayAddrStruct.UrlList.forEach(function (x) { keys.push(keyOf(x)); });
          if (video.bitrateInfo) video.bitrateInfo.forEach(function (b) { if (b.PlayAddr && b.PlayAddr.UrlList) b.PlayAddr.UrlList.forEach(function (x) { keys.push(keyOf(x)); }); });
          var author = obj.author ? (obj.author.uniqueId || obj.author.unique_id || '') : '';
          window.__faxelItems.push({ id: String(id), author: author, keys: keys });
          if (window.__faxelItems.length > 400) window.__faxelItems.shift();
        }
        for (var k in obj) { if (Object.prototype.hasOwnProperty.call(obj, k)) { var v = obj[k]; if (v && typeof v === 'object') collect(v, depth + 1); } }
      }
      var pattern = /item_list|recommend|feed|aweme|preload|related|explore/;
      function inspect(url, text) { if (!pattern.test(url || '')) return; try { collect(JSON.parse(text), 0); } catch (e) {} }
      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function () {
          var args = arguments;
          return originalFetch.apply(this, args).then(function (response) {
            try {
              var url = (args[0] && args[0].url) || String(args[0]);
              if (pattern.test(url)) response.clone().text().then(function (t) { inspect(url, t); });
            } catch (e) {}
            return response;
          });
        };
      }
      var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) { this.__faxelUrl = u; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        var x = this;
        x.addEventListener('load', function () {
          try { if (x.responseType === '' || x.responseType === 'text') inspect(String(x.__faxelUrl), x.responseText); } catch (e) {}
        });
        return send.apply(this, arguments);
      };
      document.addEventListener('DOMContentLoaded', function () {
        try {
          ['__UNIVERSAL_DATA_FOR_REHYDRATION__', 'SIGI_STATE', '__NEXT_DATA__'].forEach(function (name) {
            var node = document.getElementById(name); if (node) collect(JSON.parse(node.textContent), 0);
          });
        } catch (e) {}
      });
    })();
    """

    /// Cherche le lien de la vidéo visible à l'écran (même dans un fil qui défile).
    static let probe = """
    (function () {
      function meta(sel) { var e = document.querySelector(sel); return e ? (e.content || e.href || '') : ''; }
      function keyOf(u) { try { var x = new URL(u, location.href); return x.host + x.pathname; } catch (e) { return ''; } }
      var out = { href: location.href, og: meta('meta[property="og:url"]'), canonical: meta('link[rel="canonical"]'),
                  visible: '', src: '', title: document.title || '' };
      try {
        var best = null, bestScore = 0, videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var r = videos[i].getBoundingClientRect();
          var w = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
          var h = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
          var score = w * h + (videos[i].paused ? 0 : 1e7);
          if (w * h > 0 && score > bestScore) { bestScore = score; best = videos[i]; }
        }
        if (best) {
          var src = best.currentSrc || best.src || '';
          out.src = src;
          var keys = [keyOf(src), keyOf(best.poster || '')].filter(function (k) { return k; });
          var items = window.__faxelItems || [];
          for (var j = items.length - 1; j >= 0 && !out.visible; j--) {
            for (var q = 0; q < keys.length; q++) {
              if (items[j].keys.indexOf(keys[q]) >= 0) {
                out.visible = 'https://www.tiktok.com/@' + items[j].author + '/video/' + items[j].id; break;
              }
            }
          }
          // YouTube (page vidéo ou aperçu qui se lance tout seul dans le fil) : le lecteur connaît son identifiant.
          var player = best;
          for (var y = 0; player && y < 16 && !out.visible; y++, player = player.parentElement) {
            try {
              if (typeof player.getVideoData === 'function') {
                var data = player.getVideoData();
                if (data && data.video_id) { out.visible = 'https://www.youtube.com/watch?v=' + data.video_id; }
              }
            } catch (e) {}
          }
          var node = best;
          for (var d = 0; node && d < 14 && !out.visible; d++, node = node.parentElement) {
            var ident = (node.id || '') + ' ' + (node.getAttribute ? (node.getAttribute('data-video-id') || node.getAttribute('data-id') || '') : '');
            var m = ident.match(/(\\d{15,22})/);
            if (m && location.host.indexOf('tiktok') >= 0) { out.visible = 'https://www.tiktok.com/@/video/' + m[1]; break; }
            if (d < 8 && node.querySelector) {
              // Seulement des liens web (pas « vnd.youtube:// » du bouton « Ouvrir app »).
              var links = node.querySelectorAll('a[href*="/video/"], a[href*="/reel/"], a[href*="/reels/"], a[href*="/p/"], a[href*="/shorts/"], a[href*="watch?v="], a[href*="/status/"]');
              for (var l = 0; l < links.length && !out.visible; l++) {
                var h = links[l].href;
                if (typeof h === 'string' && h.indexOf('http') === 0) { out.visible = h; }
              }
              if (out.visible) break;
            }
          }
        }
      } catch (e) {}
      return JSON.stringify(out);
    })()
    """


    override init() {
        super.init()
        let saved = UserDefaults.standard.stringArray(forKey: "browserTabs") ?? []
        let links = saved.compactMap { URL(string: $0) }
        if links.isEmpty {
            tabs = [BrowserTab(webView: makeWebView())]
            currentIndex = 0
            bind()
            load(BrowserModel.homeLink)
        } else {
            tabs = links.map { BrowserTab(webView: makeWebView(), pending: $0) }
            currentIndex = min(max(0, UserDefaults.standard.integer(forKey: "browserTabIndex")), tabs.count - 1)
            bind()
            loadPendingIfNeeded()
        }
    }

    private func makeWebView(configuration given: WKWebViewConfiguration? = nil) -> WKWebView {
        let configuration: WKWebViewConfiguration
        if let given = given {
            configuration = given
        } else {
            configuration = WKWebViewConfiguration()
            configuration.allowsInlineMediaPlayback = true
            configuration.allowsPictureInPictureMediaPlayback = true
            configuration.websiteDataStore = .default()
            let script = WKUserScript(source: BrowserModel.touchFix, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
            let hook = WKUserScript(source: BrowserModel.feedHook, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(hook)
            let watch = WKUserScript(source: BrowserModel.mediaWatch, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(watch)
            configuration.userContentController.add(WeakScriptHandler(self), name: "faxelMedia")
            let awake = WKUserScript(source: BrowserModel.awakeWatch, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(awake)
            configuration.userContentController.add(WeakScriptHandler(self), name: "faxelAwake")
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }

    /// Suit l'onglet affiché (adresse, progression, retour…).
    private func bind() {
        observations = []
        let view = webView
        observations = [
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.sync(view) }
            },
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.sync(view) }
            },
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self = self, view === self.webView else { return }
                    self.progress = view.estimatedProgress
                }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self = self, view === self.webView else { return }
                    self.loading = view.isLoading
                }
            },
        ]
        sync(view)
        progress = view.estimatedProgress
        loading = view.isLoading
    }

    private func sync(_ view: WKWebView) {
        guard view === webView else { return }
        let link = view.url?.absoluteString ?? currentTab.pending?.absoluteString ?? ""
        if link != currentURL {
            currentURL = link
            if !link.isEmpty && !link.hasPrefix("about:") { address = link }
        }
        pageTitle = currentTab.title
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
    }

    private func loadPendingIfNeeded() {
        let tab = currentTab
        if tab.webView.url == nil, let url = tab.pending {
            tab.webView.load(URLRequest(url: url))
            tab.pending = nil
        }
    }

    func load(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var link = clean
        if !clean.lowercased().hasPrefix("http") {
            if clean.contains(".") && !clean.contains(" ") {
                link = "https://" + clean
            } else {
                let query = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
                link = "https://duckduckgo.com/?q=" + query
            }
        }
        guard let url = URL(string: link) else { return }
        address = link
        currentTab.pending = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { if webView.isLoading { webView.stopLoading() } else { webView.reload() } }

    // MARK: Onglets

    func newTab(_ link: String? = nil) {
        captureSnapshot()
        let tab = BrowserTab(webView: makeWebView())
        tabs.append(tab)
        currentIndex = tabs.count - 1
        bind()
        load(link ?? BrowserModel.homeLink)
        saveTabs()
    }

    func select(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
        bind()
        loadPendingIfNeeded()
        saveTabs()
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index].webView
        ScreenAwake.clear(prefix: "web:\(ObjectIdentifier(closing).hashValue):")
        closing.stopLoading()
        closing.navigationDelegate = nil
        closing.uiDelegate = nil
        let wasCurrent = index == currentIndex
        tabs.remove(at: index)
        if tabs.isEmpty {
            tabs = [BrowserTab(webView: makeWebView())]
            currentIndex = 0
            bind()
            load(BrowserModel.homeLink)
        } else {
            if index < currentIndex {
                currentIndex -= 1
            } else if wasCurrent {
                currentIndex = min(index, tabs.count - 1)
            }
            bind()
            loadPendingIfNeeded()
        }
        saveTabs()
    }

    func closeAllTabs() {
        for tab in tabs {
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
        }
        tabs = [BrowserTab(webView: makeWebView())]
        currentIndex = 0
        bind()
        load(BrowserModel.homeLink)
        saveTabs()
    }

    /// Image de la page affichée (pour la vue des onglets).
    func captureSnapshot(completion: (() -> Void)? = nil) {
        let tab = currentTab
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        tab.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            if let image = image { tab.snapshot = image }
            self?.objectWillChange.send()
            completion?()
        }
    }

    private func saveTabs() {
        UserDefaults.standard.set(tabs.map { $0.link }.filter { !$0.isEmpty }, forKey: "browserTabs")
        UserDefaults.standard.set(currentIndex, forKey: "browserTabIndex")
    }

    // MARK: Signets et historique

    private static func loadEntries(_ key: String) -> [BrowserEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([BrowserEntry].self, from: data) else { return [] }
        return list
    }

    private func saveEntries() {
        saveWork?.cancel()
        let history = self.history
        let bookmarks = self.bookmarks
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "browserHistory") }
            if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: "browserBookmarks") }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func remember(_ view: WKWebView) {
        guard let url = view.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let link = url.absoluteString
        let title = (view.title ?? "").isEmpty ? (url.host ?? link) : (view.title ?? link)
        if let index = history.firstIndex(where: { $0.url == link }) {
            var entry = history.remove(at: index)
            entry.visits += 1
            entry.date = Date()
            entry.title = title
            history.insert(entry, at: 0)
        } else {
            history.insert(BrowserEntry(title: title, url: link), at: 0)
            if history.count > 600 { history.removeLast(history.count - 600) }
        }
        saveEntries()
    }

    var isBookmarked: Bool {
        bookmarks.contains { $0.url == currentURL }
    }

    func toggleBookmark() {
        guard !currentURL.isEmpty else { return }
        if let index = bookmarks.firstIndex(where: { $0.url == currentURL }) {
            bookmarks.remove(at: index)
        } else {
            let title = pageTitle.isEmpty ? (URL(string: currentURL)?.host ?? currentURL) : pageTitle
            bookmarks.insert(BrowserEntry(title: title, url: currentURL), at: 0)
        }
        saveEntries()
    }

    func removeBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveEntries()
    }

    func moveBookmarks(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        saveEntries()
    }

    func removeHistory(_ ids: [String]) {
        history.removeAll { ids.contains($0.id) }
        saveEntries()
    }

    func clearHistory() {
        history = []
        saveEntries()
    }

    /// Les sites les plus visités (par domaine).
    var mostVisited: [BrowserEntry] {
        var byHost: [String: BrowserEntry] = [:]
        for entry in history {
            let host = entry.host
            if var known = byHost[host] {
                known.visits += entry.visits
                byHost[host] = known
            } else {
                var first = entry
                first.title = host
                first.url = (URL(string: entry.url)?.scheme ?? "https") + "://" + host
                byHost[host] = first
            }
        }
        return byHost.values.sorted { $0.visits > $1.visits }.prefix(8).map { $0 }
    }

    /// Suggestions pendant la saisie : signets puis historique.
    func suggestions(for text: String) -> [BrowserEntry] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, query != currentURL.lowercased() else { return [] }
        var seen = Set<String>()
        var result: [BrowserEntry] = []
        for entry in bookmarks + history {
            guard entry.title.lowercased().contains(query) || entry.url.lowercased().contains(query) else { continue }
            if seen.insert(entry.url).inserted { result.append(entry) }
            if result.count >= 10 { break }
        }
        return result
    }

    /// Meilleure adresse de vidéo pour la page affichée (la vidéo visible d'abord).
    func pageAddress(completion: @escaping (String, String) -> Void) {
        let fallback = webView.url?.absoluteString ?? ""
        webView.evaluateJavaScript(BrowserModel.probe) { result, _ in
            var object: [String: Any] = [:]
            if let text = result as? String, let data = text.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object = parsed
            }
            func value(_ key: String) -> String { (object[key] as? String) ?? "" }
            let title = value("title")
            let visible = value("visible")
            let href = value("href").isEmpty ? fallback : value("href")
            // Page vidéo YouTube : l'adresse affichée est la bonne (la vidéo principale).
            if let host = URL(string: href)?.host?.lowercased(), host.contains("youtube") || host.contains("youtu.be"),
               looksLikeVideo(href) {
                completion(href, title)
                return
            }
            if visible.lowercased().hasPrefix("http") {
                completion(visible, title)
                return
            }
            for candidate in [value("href"), value("og"), value("canonical"), fallback] where looksLikeVideo(candidate) {
                completion(candidate, title)
                return
            }
            let source = value("src")
            if source.lowercased().hasPrefix("http") {
                completion(source, title)
                return
            }
            completion(fallback, title)
        }
    }

    // MARK: Proposition de téléchargement

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "faxelAwake", let body = message.body as? [String: Any] {
            // Vidéo en lecture dans une page : pas de mise en veille de l'écran.
            let view = message.webView.map { "\(ObjectIdentifier($0).hashValue)" } ?? "?"
            let frame = body["id"] as? String ?? "?"
            ScreenAwake.set("web:" + view + ":" + frame, body["playing"] as? Bool ?? false, ttl: 7)
            return
        }
        guard message.name == "faxelMedia", let body = message.body as? [String: Any] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.videoStarted(body, in: message.webView)
        }
    }

    private func videoStarted(_ body: [String: Any], in view: WKWebView?) {
        let enabled = UserDefaults.standard.object(forKey: "askDownload") as? Bool ?? true
        guard enabled, let view = view, view === webView else { return }
        let page = body["page"] as? String ?? ""
        let source = body["src"] as? String ?? ""
        let muted = body["muted"] as? Bool ?? false
        let duration = (body["duration"] as? Double) ?? Double(body["duration"] as? Int ?? 0)
        // Aperçus muets du fil (YouTube, Facebook…) et très courtes animations : on ne dérange pas.
        if muted && !looksLikeVideo(page) { return }
        if duration > 0 && duration < 4 { return }
        let key = page + "|" + source
        guard !promptedKeys.contains(key) else { return }
        promptedKeys.insert(key)
        if promptedKeys.count > 300 { promptedKeys.removeAll() }
        mediaPrompt = true
        promptWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.mediaPrompt = false }
        promptWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: work)
    }

    func dismissPrompt() {
        promptWork?.cancel()
        mediaPrompt = false
    }

    // MARK: WKNavigationDelegate / WKUIDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync(webView)
        remember(webView)
        saveTabs()
        scheduleCookieExport()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Nouvelle page : les vidéos de l'ancienne ne comptent plus.
        ScreenAwake.clear(prefix: "web:\(ObjectIdentifier(webView).hashValue):")
        sync(webView)
    }

    /// Liens « nouvelle fenêtre » : ouverts dans un nouvel onglet.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        captureSnapshot()
        let view = makeWebView(configuration: configuration)
        tabs.append(BrowserTab(webView: view))
        currentIndex = tabs.count - 1
        bind()
        saveTabs()
        return view
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab = tabs.first(where: { $0.webView === webView }) {
            close(tab.id)
        }
    }

    // MARK: Connexions -> moteur (cookies.txt)

    func scheduleCookieExport() {
        exportWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.exportCookies() }
        exportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func exportCookies() {
        let enabled = UserDefaults.standard.object(forKey: "useCookies") as? Bool ?? true
        guard enabled else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var lines = ["# Netscape HTTP Cookie File", "# Exporté par Faxel", ""]
            for cookie in cookies {
                let domain = cookie.domain
                let flag = domain.hasPrefix(".") ? "TRUE" : "FALSE"
                let secure = cookie.isSecure ? "TRUE" : "FALSE"
                let expiry = Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
                let name = cookie.name.replacingOccurrences(of: "\t", with: " ")
                let value = cookie.value.replacingOccurrences(of: "\t", with: " ")
                lines.append([domain, flag, cookie.path, secure, String(expiry), name, value].joined(separator: "\t"))
            }
            let text = lines.joined(separator: "\n") + "\n"
            let target = PythonEngine.dataURL.appendingPathComponent("cookies.txt")
            DispatchQueue.global(qos: .utility).async {
                try? text.write(to: target, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// Affiche la page de l'onglet en cours (change de vue quand on change d'onglet).
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .systemBackground
        attach(webView, to: host)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if host.subviews.first !== webView {
            host.subviews.forEach { $0.removeFromSuperview() }
            attach(webView, to: host)
        }
    }

    private func attach(_ view: WKWebView, to host: UIView) {
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}

/// Navigateur intégré (façon Amerigo) : onglets, signets, historique, sites les
/// plus visités ; le bouton envoie la vidéo affichée à Faxel.
struct BrowserView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var jobStore: JobStore
    @FocusState private var editing: Bool
    @State private var quick: QuickLink?
    @State private var showTabs = false
    @State private var showBookmarks = false

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if !editing {
                siteChips
            }
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
                if browser.loading && browser.progress < 1 {
                    ProgressView(value: browser.progress)
                        .tint(.brand)
                }
                if editing {
                    suggestions
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if browser.mediaPrompt && !editing {
                    downloadPrompt
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: browser.mediaPrompt)
            if !editing {
                downloadBar
                toolbar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editing)
        .sheet(item: $quick) { link in
            QuickDownloadSheet(link: link)
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $showTabs) {
            BrowserTabsView()
                .environmentObject(browser)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksHistoryView()
                .environmentObject(browser)
        }
    }

    // MARK: Barre d'adresse

    private var addressBar: some View {
        HStack(spacing: 8) {
            if !editing {
                Button {
                    browser.exportCookies()
                    model.showBrowser = false
                } label: {
                    Text(L("OK"))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(height: 36)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: browser.currentURL.hasPrefix("https") && !editing ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField(L("Chercher ou saisir le nom du site…"), text: $browser.address)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .focused($editing)
                    .onSubmit {
                        browser.load(browser.address)
                        editing = false
                    }
                if editing && !browser.address.isEmpty {
                    Button {
                        browser.address = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                } else if !editing {
                    Button {
                        browser.toggleBookmark()
                    } label: {
                        Image(systemName: browser.isBookmarked ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(browser.isBookmarked ? .yellow : .secondary)
                    }
                    Button {
                        browser.reload()
                    } label: {
                        Image(systemName: browser.loading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemFill)))
            if editing {
                Button(L("Annuler")) {
                    editing = false
                    browser.address = browser.currentURL
                }
                .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var siteChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(browserSites) { site in
                    Button(site.name) {
                        browser.load(site.link)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Suggestions (les plus visités, signets, historique)

    private var suggestions: some View {
        let typed = browser.address.trimmingCharacters(in: .whitespaces)
        let matches = browser.suggestions(for: typed)
        return List {
            if !matches.isEmpty {
                Section(L("Suggestions")) {
                    ForEach(matches) { entry in
                        entryRow(entry, icon: browser.bookmarks.contains(where: { $0.url == entry.url }) ? "star.fill" : "clock")
                    }
                }
            }
            if !typed.isEmpty && typed != browser.currentURL {
                Section {
                    Button {
                        browser.load(typed)
                        editing = false
                    } label: {
                        Label(L("Rechercher « {text} »", ["text": typed]), systemImage: "magnifyingglass")
                            .foregroundColor(.primary)
                    }
                }
            }
            let top = browser.mostVisited
            if !top.isEmpty {
                Section(L("Les plus visités")) {
                    ForEach(top) { entry in
                        entryRow(entry, icon: "globe")
                    }
                }
            }
            if !browser.bookmarks.isEmpty && typed.isEmpty {
                Section(L("Signets")) {
                    ForEach(browser.bookmarks.prefix(8)) { entry in
                        entryRow(entry, icon: "star.fill")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private func entryRow(_ entry: BrowserEntry, icon: String) -> some View {
        Button {
            browser.load(entry.url)
            editing = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(icon == "star.fill" ? .yellow : .brand)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(entry.url)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// « Voulez-vous télécharger ce contenu ? » ✓ / ✗ (comme Amerigo).
    private var downloadPrompt: some View {
        HStack(spacing: 14) {
            Text(L("Voulez-vous télécharger ce contenu ?"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                browser.dismissPrompt()
                downloadPage(queueNow: true)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.green)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Color.green, lineWidth: 2))
            }
            Button {
                browser.dismissPrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.red)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Color.red, lineWidth: 2))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.17).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
    }

    // MARK: Téléchargement et barre d'outils

    private var downloadBar: some View {
        VStack(spacing: 4) {
            Button {
                downloadPage()
            } label: {
                Label(L("Télécharger cette vidéo"), systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            let active = jobStore.jobs.filter { $0.active }.count
            if active > 0 {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(L("{count} téléchargement(s) en cours", ["count": "\(active)"]))
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private var toolbar: some View {
        HStack {
            toolButton("chevron.left", enabled: browser.canGoBack) { browser.goBack() }
            Spacer()
            toolButton("chevron.right", enabled: browser.canGoForward) { browser.goForward() }
            Spacer()
            if let url = URL(string: browser.currentURL), !browser.currentURL.isEmpty {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 40)
                }
            } else {
                toolButton("square.and.arrow.up", enabled: false) {}
            }
            Spacer()
            toolButton("book", enabled: true) { showBookmarks = true }
            Spacer()
            Button {
                browser.captureSnapshot {
                    showTabs = true
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.brand, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Text("\(browser.tabs.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.brand)
                }
                .frame(width: 44, height: 40)
            }
            .contextMenu {
                Button {
                    browser.newTab()
                } label: {
                    Label(L("Nouvel onglet"), systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    browser.close(browser.currentTab.id)
                } label: {
                    Label(L("Fermer cet onglet"), systemImage: "xmark")
                }
            }
        }
        .foregroundColor(.brand)
        .padding(.horizontal, 22)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func toolButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 40)
        }
        .disabled(!enabled)
    }

    /// `queueNow` : ajouté tout de suite à la file avec la qualité par défaut,
    /// on reste dans le navigateur pour continuer à défiler et en ajouter d'autres.
    private func downloadPage(queueNow: Bool = false) {
        editing = false
        browser.pageAddress { link, title in
            guard link.lowercased().hasPrefix("http") else {
                model.show(L("Aucune page ouverte."), .warn)
                return
            }
            if !looksLikeVideo(link), let host = URL(string: link)?.host?.lowercased(),
               ["youtube", "youtu.be", "tiktok", "facebook", "fb.watch", "instagram", "twitter", "x.com"]
                .contains(where: { host.contains($0) }) {
                model.show(L("Aucune vidéo trouvée sur cette page : ouvrez la vidéo (touchez-la), puis touchez à nouveau le bouton."),
                           .warn)
                return
            }
            browser.exportCookies()
            if queueNow {
                let media = UserDefaults.standard.string(forKey: "defaultMedia") ?? "video"
                let quality = UserDefaults.standard.string(forKey: "defaultQuality") ?? "Meilleure"
                let clean = title.replacingOccurrences(of: " - YouTube", with: "")
                model.quickDownload([["url": link, "title": clean]], media: media,
                                    quality: media == "audio" ? "Meilleure" : quality)
                return
            }
            quick = QuickLink(url: link, title: title)
        }
    }
}

// MARK: - Vue des onglets

struct BrowserTabsView: View {
    @EnvironmentObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCloseAll = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(L("{count} onglet(s)", ["count": "\(browser.tabs.count)"]))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(L("Tout fermer")) { confirmCloseAll = true }
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(browser.tabs) { tab in
                                card(tab)
                                    .id(tab.id)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                    }
                    .onAppear {
                        proxy.scrollTo(browser.currentTab.id, anchor: .center)
                    }
                }
                .frame(maxHeight: .infinity)

                Text(browser.currentTab.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                HStack {
                    Spacer()
                    Button {
                        browser.newTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.brand)
                            .frame(width: 60, height: 50)
                    }
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button(L("OK")) { dismiss() }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.brand)
                        .padding(.trailing, 22)
                }
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
            }
        }
        .confirmationDialog(L("Fermer tous les onglets ?"), isPresented: $confirmCloseAll, titleVisibility: .visible) {
            Button(L("Tout fermer"), role: .destructive) {
                browser.closeAllTabs()
                dismiss()
            }
        }
    }

    private func card(_ tab: BrowserTab) -> some View {
        let isCurrent = tab.id == browser.currentTab.id
        return Button {
            browser.select(tab.id)
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = tab.snapshot {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(.systemBackground)
                            VStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 34))
                                    .foregroundColor(.brand)
                                Text(tab.title)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                }
                .frame(width: 210, height: 380, alignment: .top)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isCurrent ? Color.brand : Color.white.opacity(0.15), lineWidth: isCurrent ? 3 : 1)
                )
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        browser.close(tab.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.9)))
                        .shadow(radius: 3)
                }
                .offset(x: 8, y: -8)
            }
            .scaleEffect(isCurrent ? 1 : 0.94)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Signets et historique

struct BookmarksHistoryView: View {
    @EnvironmentObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var section = "bookmarks"
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    Text(L("Signets")).tag("bookmarks")
                    Text(L("Historique")).tag("history")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if section == "bookmarks" {
                    bookmarksList
                } else {
                    historyList
                }
            }
            .navigationTitle(L("Signets et historique"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if section == "bookmarks" && !browser.bookmarks.isEmpty {
                        EditButton()
                    } else if section == "history" && !browser.history.isEmpty {
                        Button(L("Effacer")) { confirmClear = true }
                            .foregroundColor(.red)
                    }
                }
            }
            .confirmationDialog(L("Effacer tout l'historique ?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L("Effacer l'historique"), role: .destructive) { browser.clearHistory() }
            }
        }
    }

    @ViewBuilder
    private var bookmarksList: some View {
        if browser.bookmarks.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "star")
                    .font(.system(size: 40))
                    .foregroundColor(.brand)
                Text(L("Aucun signet"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brand)
                Text(L("Touchez l'étoile dans la barre d'adresse pour garder une page."))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
                Spacer()
            }
        } else {
            List {
                ForEach(browser.bookmarks) { entry in
                    row(entry, icon: "star.fill")
                }
                .onDelete { browser.removeBookmarks(at: $0) }
                .onMove { browser.moveBookmarks(from: $0, to: $1) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if browser.history.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundColor(.brand)
                Text(L("Aucun historique"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.brand)
                Spacer()
                Spacer()
            }
        } else {
            let groups = grouped(browser.history)
            List {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { entry in
                            row(entry, icon: "clock")
                                .swipeActions {
                                    Button(role: .destructive) {
                                        browser.removeHistory([entry.id])
                                    } label: {
                                        Label(L("Supprimer"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func grouped(_ entries: [BrowserEntry]) -> [(title: String, items: [BrowserEntry])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateStyle = .full
        var order: [String] = []
        var map: [String: [BrowserEntry]] = [:]
        for entry in entries {
            let title: String
            if calendar.isDateInToday(entry.date) {
                title = L("Aujourd'hui")
            } else if calendar.isDateInYesterday(entry.date) {
                title = L("Hier")
            } else {
                title = formatter.string(from: entry.date)
            }
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(entry)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func row(_ entry: BrowserEntry, icon: String) -> some View {
        Button {
            browser.load(entry.url)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(icon == "star.fill" ? .yellow : .brand)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(entry.url)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contextMenu {
            Button {
                browser.newTab(entry.url)
                dismiss()
            } label: {
                Label(L("Ouvrir dans un nouvel onglet"), systemImage: "plus.square.on.square")
            }
            Button {
                UIPasteboard.general.string = entry.url
            } label: {
                Label(L("Copier le lien"), systemImage: "doc.on.doc")
            }
        }
    }
}
