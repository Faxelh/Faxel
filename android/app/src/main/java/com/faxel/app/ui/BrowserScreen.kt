package com.faxel.app.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.faxel.app.R
import com.faxel.app.data.Prefs
import com.faxel.app.data.WebLink
import com.faxel.app.engine.Engine
import java.net.URLEncoder

data class Site(val name: String, val url: String, val colors: List<Color>)

val sites = listOf(
    Site("YouTube", "https://m.youtube.com", listOf(Color(0xFFFF0000), Color(0xFFB00000))),
    Site("Instagram", "https://www.instagram.com", listOf(Color(0xFFF58529), Color(0xFFDD2A7B))),
    Site("Facebook", "https://m.facebook.com", listOf(Color(0xFF1877F2), Color(0xFF0A4CB3))),
    Site("X", "https://x.com", listOf(Color(0xFF333333), Color(0xFF000000))),
    Site("Vimeo", "https://vimeo.com", listOf(Color(0xFF1AB7EA), Color(0xFF0E7FA5))),
    Site("Dailymotion", "https://www.dailymotion.com", listOf(Color(0xFF0066DC), Color(0xFF00A3FF))),
    Site("SoundCloud", "https://m.soundcloud.com", listOf(Color(0xFFFF5500), Color(0xFFFF8800))),
)

/** Navigateur intégré : une seule WebView gardée pendant toute la vie de l'app. */
object Browser {
    /** Signale à l'app si une vidéo joue dans la page (reels, YouTube…). */
    private const val AWAKE_SCRIPT = """
(function () {
  if (window.__faxelAwake) return; window.__faxelAwake = true;
  var last = null;
  function playing() {
    var list = document.querySelectorAll('video');
    for (var i = 0; i < list.length; i++) {
      var v = list[i];
      if (!v.paused && !v.ended && v.readyState >= 2) return true;
    }
    return false;
  }
  function report() {
    var now = playing();
    if (now || now !== last) { try { FaxelAwake.state(now); } catch (e) {} }
    last = now;
  }
  ['play', 'playing', 'pause', 'ended', 'emptied', 'abort'].forEach(function (name) {
    document.addEventListener(name, function () { setTimeout(report, 50); }, true);
  });
  document.addEventListener('visibilitychange', report);
  window.__faxelAwakeReport = function () { last = null; report(); };
  setInterval(report, 2000);
  report();
})();
"""

    /** Vidéo en lecture dans la page : l'écran ne se met pas en veille. */
    private class AwakeBridge(private val web: WebView) {
        @JavascriptInterface
        fun state(playing: Boolean) {
            web.post {
                web.removeCallbacks(expire)
                web.keepScreenOn = playing && web.visibility == View.VISIBLE
                // La page redonne des nouvelles toutes les 2 s pendant la lecture ;
                // sans nouvelles depuis 7 s, l'écran peut de nouveau se mettre en veille.
                if (playing) web.postDelayed(expire, 7_000)
            }
        }

        private val expire = Runnable { web.keepScreenOn = false }
    }

    private var view: WebView? = null
    var url by mutableStateOf("")
    var title by mutableStateOf("")
    var progress by mutableIntStateOf(100)
    var canGoBack by mutableStateOf(false)
    var canGoForward by mutableStateOf(false)
    var home by mutableStateOf(true)
    var prompt by mutableStateOf<String?>(null)
    private val dismissed = HashSet<String>()

    /** État (historique, page) gardé quand la WebView est recréée (rotation, tablette ↔ téléphone). */
    private var saved: Bundle? = null

    /**
     * Crée la WebView de l'écran. Une WebView n'est jamais déplacée d'un écran à l'autre
     * (cela la dessinait par-dessus la barre d'adresse et le menu sur tablette) :
     * on la recrée et on lui rend son historique.
     */
    @SuppressLint("SetJavaScriptEnabled")
    fun create(context: Context): WebView {
        val web = WebView(context)
        web.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        web.setBackgroundColor(android.graphics.Color.rgb(11, 11, 15))
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = true
            displayZoomControls = false
            setSupportMultipleWindows(false)
        }
        web.addJavascriptInterface(AwakeBridge(web), "FaxelAwake")
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme ?: return false
                return scheme != "http" && scheme != "https"
            }

            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                view.keepScreenOn = false
                update(view)
            }

            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript(AWAKE_SCRIPT, null)
                update(view)
                Prefs.visit(url, view.title ?: "")
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = update(view)
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progress = newProgress
                // Les sites qui chargent sans fin (fil de reels) : le guetteur est posé tôt.
                if (newProgress >= 60) view.evaluateJavascript(AWAKE_SCRIPT, null)
            }

            override fun onReceivedTitle(view: WebView, title: String?) {
                this@Browser.title = title ?: ""
            }
        }
        saved?.let { web.restoreState(it) }
        saved = null
        view = web
        pending?.let {
            web.loadUrl(it)
            pending = null
        }
        return web
    }

    fun release(web: WebView) {
        saved = Bundle().also { web.saveState(it) }
        web.keepScreenOn = false
        web.removeJavascriptInterface("FaxelAwake")
        web.stopLoading()
        web.destroy()
        if (view === web) view = null
    }

    fun setVisible(visible: Boolean) {
        val web = view ?: return
        web.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        if (!visible) web.keepScreenOn = false
        else web.evaluateJavascript("window.__faxelAwakeReport && window.__faxelAwakeReport()", null)
        // Onglet caché : la vidéo de la page se met en pause.
        if (visible) web.onResume() else web.onPause()
    }

    fun goForward() {
        view?.goForward()
        home = false
    }

    fun reload() {
        view?.reload()
    }

    private fun update(web: WebView) {
        val current = web.url ?: return
        url = current
        title = web.title ?: ""
        canGoBack = web.canGoBack()
        canGoForward = web.canGoForward()
        prompt = if (Prefs.askDownload.value && isMediaPage(current) && current !in dismissed) current else null
    }

    fun load(input: String) {
        val text = input.trim()
        if (text.isEmpty()) return
        val target = when {
            text.startsWith("http://") || text.startsWith("https://") -> text
            !text.contains(' ') && text.contains('.') -> "https://$text"
            else -> searchUrl(text)
        }
        home = false
        view?.loadUrl(target) ?: run { pending = target }
    }

    var pending: String? = null

    fun searchUrl(query: String): String {
        val q = URLEncoder.encode(query, "UTF-8")
        return when (Prefs.searchEngine.value) {
            "duckduckgo" -> "https://duckduckgo.com/?q=$q"
            "bing" -> "https://www.bing.com/search?q=$q"
            "youtube" -> "https://m.youtube.com/results?search_query=$q"
            else -> "https://www.google.com/search?q=$q"
        }
    }

    fun back() {
        val web = view ?: return
        if (web.canGoBack()) web.goBack() else home = true
    }

    fun dismiss() {
        prompt?.let { dismissed += it }
        prompt = null
    }

    /** Page d'une vidéo, d'un son ou d'une publication (pas l'accueil d'un site). */
    fun isMediaPage(link: String): Boolean {
        val l = link.lowercase()
        return when {
            "youtube.com/watch" in l || "youtube.com/shorts/" in l || "youtu.be/" in l -> true
            "tiktok.com" in l -> "/video/" in l || "/photo/" in l || "vm.tiktok.com" in l || "vt.tiktok.com" in l
            "instagram.com" in l -> "/p/" in l || "/reel" in l || "/tv/" in l
            "facebook.com" in l || "fb.watch" in l -> "/watch" in l || "/reel" in l || "/videos/" in l || "fb.watch" in l
            "x.com/" in l || "twitter.com/" in l -> "/status/" in l
            "vimeo.com/" in l -> Regex("""vimeo\.com/\d+""").containsMatchIn(l)
            "dailymotion.com/video" in l -> true
            "soundcloud.com/" in l -> l.substringAfter("soundcloud.com/").substringBefore('?').trim('/').count { it == '/' } >= 1
            else -> false
        }
    }
}

@Composable
fun BrowserScreen(onDownload: () -> Unit, visible: Boolean = true) {
    val focus = LocalFocusManager.current
    var address by remember { mutableStateOf("") }
    var editing by remember { mutableStateOf(false) }
    var panel by remember { mutableStateOf<String?>(null) }
    val wide = Layout.wide

    LaunchedEffect(visible) { Browser.setVisible(visible) }

    fun sendToDownload(link: String) {
        Engine.pendingAutoDownload = false
        Engine.pendingLink = link
        Browser.dismiss()
        onDownload()
    }

    val context = LocalContext.current
    val queuedText = stringResource(R.string.browser_queued)

    /** Ajoute directement à la file de téléchargement : on reste dans le navigateur. */
    fun queue(link: String) {
        Browser.dismiss()
        val media = Prefs.defaultMedia.value
        val title = Browser.title.removeSuffix(" - YouTube").trim()
        Engine.download(listOf(Triple(link, title, null)), media, if (media == "audio") BEST else Prefs.defaultQuality.value)
        android.widget.Toast.makeText(context, queuedText, android.widget.Toast.LENGTH_SHORT).show()
    }

    val canBack = Browser.canGoBack || !Browser.home
    val canDownload = !Browser.home && Browser.url.isNotBlank()

    @Composable
    fun BackButton() = IconButton(onClick = { Browser.back() }, enabled = canBack) {
        Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = if (canBack) Color.White else Muted)
    }

    @Composable
    fun ForwardButton() = IconButton(onClick = { Browser.goForward() }, enabled = Browser.canGoForward) {
        Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, tint = if (Browser.canGoForward) Color.White else Muted)
    }

    @Composable
    fun ReloadButton() = IconButton(onClick = { Browser.reload() }, enabled = !Browser.home) {
        Icon(Icons.Rounded.Refresh, null, tint = if (!Browser.home) Color.White else Muted)
    }

    @Composable
    fun HistoryButton() = IconButton(onClick = { panel = if (panel == null) "history" else null }) {
        Icon(Icons.Rounded.History, null, tint = if (panel != null) accent else Color.White)
    }

    @Composable
    fun DownloadButton(size: Int) = Box(
        Modifier.padding(vertical = 6.dp).size(size.dp).clip(CircleShape)
            .background(
                if (canDownload) Brush.linearGradient(listOf(accent, Color(0xFFFF2D60)))
                else Brush.linearGradient(listOf(Surface2, Surface2)),
            )
            // Toucher : ajouté à la file (on continue à naviguer) ; appui long : choisir la qualité.
            .pointerInput(canDownload) {
                if (canDownload) {
                    detectTapGestures(
                        onTap = { queue(Browser.url) },
                        onLongPress = { sendToDownload(Browser.url) },
                    )
                }
            },
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Rounded.Download, null, tint = if (canDownload) Color.White else Muted) }

    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B0F))
            .windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal)),
    ) {
        // Barre d'adresse (sur tablette : tous les boutons sont ici, comme Chrome)
        Row(
            Modifier
                .fillMaxWidth()
                .background(Surface1)
                .statusBarsPadding()
                .padding(horizontal = if (wide) 8.dp else 4.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (wide) {
                BackButton()
                ForwardButton()
                ReloadButton()
            }
            IconButton(onClick = { Browser.home = true; panel = null }) { Icon(Icons.Rounded.Home, null, tint = accent) }
            androidx.compose.foundation.text.BasicTextField(
                value = if (editing) address else (if (Browser.home) "" else Browser.url),
                onValueChange = { address = it; editing = true },
                singleLine = true,
                textStyle = androidx.compose.ui.text.TextStyle(color = Color.White, fontSize = 15.sp),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(accent),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = {
                    Browser.load(address)
                    editing = false
                    focus.clearFocus()
                }),
                decorationBox = { inner ->
                    Box(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Surface2)
                            .padding(horizontal = 14.dp, vertical = 11.dp),
                    ) {
                        if ((editing && address.isEmpty()) || (!editing && (Browser.home || Browser.url.isEmpty()))) {
                            Text(stringResource(R.string.address_hint), color = Muted, fontSize = 15.sp, maxLines = 1)
                        }
                        inner()
                    }
                },
                modifier = Modifier.weight(1f),
            )
            if (editing) {
                IconButton(onClick = { editing = false; address = ""; focus.clearFocus() }) { Icon(Icons.Rounded.Close, null, tint = Muted) }
            } else if (!Browser.home) {
                IconButton(onClick = { Prefs.toggleBookmark(Browser.url, Browser.title) }) {
                    Icon(if (Prefs.isBookmarked(Browser.url)) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder, null, tint = accent)
                }
            }
            if (wide) {
                HistoryButton()
                Spacer(Modifier.width(4.dp))
                DownloadButton(40)
            }
        }
        if (Browser.progress < 100 && !Browser.home) {
            LinearProgressIndicator(progress = { Browser.progress / 100f }, modifier = Modifier.fillMaxWidth().height(2.dp))
        }

        Box(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
            AndroidView(
                factory = { ctx -> Browser.create(ctx) },
                onRelease = { web -> Browser.release(web) },
                modifier = Modifier.fillMaxSize(),
            )
            if (Browser.home) {
                BrowserHome(onOpen = { Browser.load(it); panel = null })
            }
            panel?.let { kind ->
                LinkPanel(kind, onOpen = { Browser.load(it); panel = null }, onClose = { panel = null })
            }
            // « Voulez-vous télécharger ce contenu ? »
            val prompt = Browser.prompt
            if (prompt != null && !Browser.home && panel == null) {
                Row(
                    Modifier.align(Alignment.BottomCenter).padding(12.dp).widthIn(max = 560.dp).fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp)).background(Surface2).padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.Download, null, tint = accent)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.browser_prompt), color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    TextButton(onClick = { Browser.dismiss() }) { Text(stringResource(R.string.no), color = Muted) }
                    Button(onClick = { queue(prompt) }) { Text(stringResource(R.string.yes)) }
                }
            }
        }

        // Barre d'outils du bas (téléphone seulement)
        if (!wide) {
            Row(
                Modifier.fillMaxWidth().background(Surface1).padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BackButton()
                ForwardButton()
                DownloadButton(44)
                ReloadButton()
                HistoryButton()
            }
        }
    }
}

@Composable
private fun BrowserHome(onOpen: (String) -> Unit) {
    val wide = Layout.wide
    Box(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).blockTouches(), contentAlignment = Alignment.TopCenter) {
        LazyVerticalGrid(
            GridCells.Adaptive(if (wide) 104.dp else 78.dp),
            Modifier.fillMaxHeight().widthIn(max = 960.dp).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(stringResource(R.string.favorite_sites), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            items(sites, key = { it.name }) { site ->
                Column(
                    Modifier.clip(RoundedCornerShape(16.dp)).clickable { onOpen(site.url) }.padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        Modifier.size(if (wide) 64.dp else 56.dp).clip(RoundedCornerShape(16.dp)).background(Brush.linearGradient(site.colors)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(site.name.take(1), color = Color.White, fontSize = if (wide) 26.sp else 22.sp, fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(site.name, color = Color.White, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            val bookmarks = Prefs.bookmarks.value
            val recent = Prefs.history.value.take(if (wide) 10 else 8)
            if (wide && bookmarks.isNotEmpty() && recent.isNotEmpty()) {
                // Tablette : favoris et pages récentes côte à côte.
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.bookmarks), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                            bookmarks.take(10).forEach { link -> LinkRow(link, onOpen) { Prefs.removeBookmark(link.url) } }
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.recent_pages), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                            recent.forEach { link -> LinkRow(link, onOpen, null) }
                        }
                    }
                }
            } else {
                if (bookmarks.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Text(stringResource(R.string.bookmarks), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
                    }
                    items(bookmarks, key = { "b-" + it.url }, span = { GridItemSpan(maxLineSpan) }) { link -> LinkRow(link, onOpen) { Prefs.removeBookmark(link.url) } }
                }
                if (recent.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Text(stringResource(R.string.recent_pages), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
                    }
                    items(recent, key = { "h-" + it.url }, span = { GridItemSpan(maxLineSpan) }) { link -> LinkRow(link, onOpen, null) }
                }
            }
        }
    }
}

@Composable
private fun LinkRow(link: WebLink, onOpen: (String) -> Unit, onRemove: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { onOpen(link.url) }.background(Surface1).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(link.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(link.url, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onRemove != null) IconButton(onClick = onRemove) { Icon(Icons.Rounded.Close, null, tint = Muted) }
    }
}

@Composable
private fun LinkPanel(kind: String, onOpen: (String) -> Unit, onClose: () -> Unit) {
    var showing by remember { mutableStateOf(kind) }
    Column(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).blockTouches()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Chip(stringResource(R.string.history), showing == "history") { showing = "history" }
            Spacer(Modifier.width(8.dp))
            Chip(stringResource(R.string.bookmarks), showing == "bookmarks") { showing = "bookmarks" }
            Spacer(Modifier.weight(1f))
            if (showing == "history") TextButton(onClick = { Prefs.clearHistory() }) { Text(stringResource(R.string.clear)) }
            IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, null, tint = Muted) }
        }
        val links = if (showing == "history") Prefs.history.value else Prefs.bookmarks.value
        if (links.isEmpty()) EmptyState(stringResource(R.string.nothing_here))
        androidx.compose.foundation.lazy.LazyColumn(
            contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(links.size, key = { showing + links[it].url }) { i ->
                val link = links[i]
                LinkRow(link, onOpen, if (showing == "bookmarks") ({ Prefs.removeBookmark(link.url) }) else null)
            }
        }
    }
}
