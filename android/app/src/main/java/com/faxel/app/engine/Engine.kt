package com.faxel.app.engine

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.webkit.CookieManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.faxel.app.data.Analysis
import com.faxel.app.data.Entry
import com.faxel.app.data.Job
import com.faxel.app.data.Playlist
import com.faxel.app.data.SearchResult
import com.faxel.app.data.objects
import com.faxel.app.data.str
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.util.Locale

/** Message court affiché en bas de l'écran (fin d'import, erreur…). */
data class Notice(val text: String, val path: String? = null, val error: Boolean = false, val stamp: Long = System.nanoTime())

/**
 * Le moteur Python de Faxel (yt-dlp + mp4mux), le même que sur iPhone,
 * appelé avec dispatch(nom, json) → json.
 */
object Engine {
    private const val TAG = "Faxel"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var appContext: Context
    private var bridge: PyObject? = null

    var ready by mutableStateOf(false)
        private set
    var startError by mutableStateOf<String?>(null)
        private set
    var root: File? by mutableStateOf(null)
        private set
    var python by mutableStateOf("")
        private set
    var ytdlp by mutableStateOf("")
        private set
    var javascript by mutableStateOf(false)
        private set

    var jobs by mutableStateOf<List<Job>>(emptyList())
        private set
    var active by mutableStateOf(false)
        private set
    var entries by mutableStateOf<List<Entry>>(emptyList())
        private set
    var favorites by mutableStateOf<Set<String>>(emptySet())
        private set
    var playlists by mutableStateOf<List<Playlist>>(emptyList())
        private set
    var vault by mutableStateOf<List<Entry>>(emptyList())
        private set
    var settings by mutableStateOf(JSONObject())
        private set
    var notice by mutableStateOf<Notice?>(null)

    /** Lien reçu (partage, presse-papiers, navigateur, recherche) à analyser dans l'onglet Télécharger. */
    var pendingLink by mutableStateOf<String?>(null)
    var pendingAutoDownload by mutableStateOf(false)

    private var libraryRev = -1

    fun start(context: Context, language: String) {
        if (::appContext.isInitialized) return
        appContext = context.applicationContext
        JsEngine.init(appContext)
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    if (!Python.isStarted()) Python.start(AndroidPlatform(appContext))
                    val module = Python.getInstance().getModule("faxel.bridge")
                    bridge = module
                    val target = Storage.root(appContext)
                    val data = File(appContext.filesDir, "data").apply { mkdirs() }
                    Storage.migrate(appContext, data, target)
                    root = target
                    val args = JSONObject()
                        .put("documents", target.absolutePath)
                        .put("data", data.absolutePath)
                        .put("cache", File(appContext.cacheDir, "engine").absolutePath)
                        .put("language", pyLanguage(language))
                    JSONObject(module.callAttr("dispatch", "init", args.toString()).toString())
                }
            }
            result.onSuccess { info ->
                if (info.has("error")) {
                    startError = info.str("error")
                } else {
                    python = info.str("python")
                    ytdlp = info.str("ytdlp")
                    javascript = info.optBoolean("javascript")
                    ready = true
                    refreshLibrary(force = true)
                    loadSettings()
                    pollLoop()
                }
            }.onFailure {
                Log.e(TAG, "Démarrage du moteur impossible", it)
                startError = it.message ?: it.javaClass.simpleName
            }
        }
    }

    private fun pyLanguage(language: String): String {
        val code = language.ifBlank { Locale.getDefault().language }
        return if (code.startsWith("fr")) "fr" else "en"
    }

    /** Appel au moteur (hors du fil de l'interface). */
    suspend fun call(op: String, args: JSONObject = JSONObject()): JSONObject = withContext(Dispatchers.IO) {
        val module = bridge ?: return@withContext JSONObject().put("error", "moteur non démarré")
        runCatching { JSONObject(module.callAttr("dispatch", op, args.toString()).toString()) }
            .getOrElse { JSONObject().put("error", it.message ?: "Python") }
    }

    fun fire(op: String, args: JSONObject = JSONObject(), then: (JSONObject) -> Unit = {}) {
        scope.launch { then(call(op, args)) }
    }

    fun setLanguage(language: String) = fire("language", JSONObject().put("language", pyLanguage(language)))

    // MARK: Imports

    private fun pollLoop() {
        scope.launch {
            while (true) {
                val result = call("poll")
                if (!result.has("error")) {
                    jobs = result.optJSONArray("jobs").objects().map { Job.from(it) }
                    val wasActive = active
                    active = result.optBoolean("active")
                    handleEvents(result.optJSONArray("events"))
                    if (result.optInt("rev", -1) != libraryRev) refreshLibrary()
                    if (active != wasActive) updateService()
                }
                delay(if (active) 700 else 2500)
            }
        }
    }

    private fun handleEvents(events: JSONArray?) {
        events.objects().forEach { event ->
            when (event.str("kind")) {
                "finished" -> {
                    val path = event.str("filepath")
                    if (Storage.isPublic) Storage.scan(appContext, path)
                    notice = Notice(event.str("title"), path)
                    DownloadService.finished(appContext, event.str("title"))
                }
                "failed" -> notice = Notice(event.str("title") + " — " + event.str("message"), error = true)
            }
        }
    }

    private fun updateService() {
        val intent = Intent(appContext, DownloadService::class.java)
        if (active) {
            runCatching {
                if (Build.VERSION.SDK_INT >= 26) ContextCompat.startForegroundService(appContext, intent)
                else appContext.startService(intent)
            }
        }
    }

    fun analyze(url: String, playlist: Boolean = false, done: (Analysis?, String?) -> Unit) {
        scope.launch {
            exportCookies(url)
            val result = call("analyze", JSONObject().put("url", url).put("playlist", playlist))
            val info = result.optJSONObject("info")
            when {
                info != null -> done(Analysis.from(info), null)
                result.has("error_message") -> done(null, result.str("error_message"))
                else -> done(null, result.str("error").ifBlank { "?" })
            }
        }
    }

    fun download(items: List<Triple<String, String, String?>>, mediaType: String, quality: String, done: (Int) -> Unit = {}) {
        val array = JSONArray()
        items.forEach { (url, title, platform) ->
            array.put(JSONObject().put("url", url).put("title", title).put("platform", platform ?: JSONObject.NULL))
        }
        val args = JSONObject().put("items", array).put("media_type", mediaType).put("quality", quality)
        scope.launch {
            items.firstOrNull()?.let { exportCookies(it.first) }
            val result = call("import", args)
            done(result.optInt("count"))
            nudge()
        }
    }

    fun downloadText(text: String, mediaType: String, quality: String, done: (Int) -> Unit = {}) {
        scope.launch {
            val result = call("import_text", JSONObject().put("text", text).put("media_type", mediaType).put("quality", quality))
            done(result.optInt("count"))
            nudge()
        }
    }

    private fun nudge() {
        active = true
        updateService()
    }

    fun job(action: String, id: String? = null) {
        val args = JSONObject().put("action", action)
        if (id != null) args.put("id", id)
        fire("job", args)
    }

    fun search(query: String, done: (List<SearchResult>) -> Unit) {
        scope.launch {
            val result = call("search", JSONObject().put("query", query).put("limit", 30))
            done(result.optJSONArray("results").objects().map { SearchResult.from(it) }.filter { it.url.isNotBlank() })
        }
    }

    /** Cookies du navigateur intégré (comptes connectés) transmis à yt-dlp. */
    private suspend fun exportCookies(url: String) {
        if (!settings.optBoolean("use_browser_cookies")) return
        val host = runCatching { URI(url).host }.getOrNull() ?: return
        val cookies = withContext(Dispatchers.Main) { runCatching { CookieManager.getInstance().getCookie(url) }.getOrNull() } ?: return
        withContext(Dispatchers.IO) {
            runCatching {
                val domain = "." + host.removePrefix("www.").removePrefix("m.")
                val expiry = System.currentTimeMillis() / 1000 + 30L * 24 * 3600
                val lines = StringBuilder("# Netscape HTTP Cookie File\n")
                cookies.split(";").map { it.trim() }.filter { it.contains('=') }.forEach { pair ->
                    val name = pair.substringBefore('=')
                    val value = pair.substringAfter('=')
                    lines.append("$domain\tTRUE\t/\tTRUE\t$expiry\t$name\t$value\n")
                }
                File(appContext.filesDir, "data/cookies.txt").writeText(lines.toString())
            }
        }
    }

    // MARK: Bibliothèque

    fun refreshLibrary(force: Boolean = false) {
        scope.launch {
            val result = call("library")
            if (result.has("error")) return@launch
            val rev = result.optInt("rev", -1)
            if (!force && rev == libraryRev && entries.isNotEmpty()) return@launch
            libraryRev = rev
            entries = result.optJSONArray("entries").objects().map { Entry.from(it) }.filter { it.path.isNotBlank() }
            val favs = result.optJSONArray("favorites")
            favorites = if (favs == null) emptySet() else (0 until favs.length()).map { favs.optString(it) }.toSet()
            playlists = result.optJSONArray("playlists").objects().map { Playlist.from(it) }
            vault = result.optJSONArray("vault").objects().map { Entry.from(it) }
        }
    }

    fun rescan(done: (Int) -> Unit = {}) {
        scope.launch {
            val result = call("rescan")
            refreshLibrary(force = true)
            done(result.optInt("added"))
        }
    }

    private fun entryJson(entry: Entry) = JSONObject()
        .put("uid", entry.uid).put("filepath", entry.path).put("title", entry.title)
        .put("thumbnail", entry.thumbnail ?: JSONObject.NULL).put("duration", entry.duration ?: JSONObject.NULL)

    fun isFavorite(entry: Entry) = entry.path in favorites

    fun toggleFavorite(entry: Entry) {
        favorites = if (entry.path in favorites) favorites - entry.path else favorites + entry.path
        fire("toggle_favorite", JSONObject().put("entry", entryJson(entry))) { refreshLibrary(force = true) }
    }

    fun delete(entry: Entry) {
        entries = entries.filter { it.path != entry.path }
        fire("delete", JSONObject().put("entry", entryJson(entry))) { refreshLibrary(force = true) }
    }

    fun createPlaylist(name: String, then: (String) -> Unit = {}) {
        fire("playlist_create", JSONObject().put("name", name)) { refreshLibrary(force = true); then(it.str("uid")) }
    }

    fun renamePlaylist(id: String, name: String) = fire("playlist_rename", JSONObject().put("uid", id).put("name", name)) { refreshLibrary(force = true) }
    fun deletePlaylist(id: String) = fire("playlist_delete", JSONObject().put("uid", id)) { refreshLibrary(force = true) }
    fun addToPlaylist(id: String, entry: Entry) =
        fire("playlist_add", JSONObject().put("uid", id).put("entry", entryJson(entry))) { refreshLibrary(force = true) }
    fun removeFromPlaylist(id: String, path: String) =
        fire("playlist_remove", JSONObject().put("uid", id).put("filepath", path)) { refreshLibrary(force = true) }

    fun hide(entry: Entry) = fire("vault_add", JSONObject().put("entry", entryJson(entry))) { refreshLibrary(force = true) }
    fun unhide(entry: Entry) = fire("vault_remove", JSONObject().put("item", JSONObject().put("filepath", entry.path))) { refreshLibrary(force = true) }

    fun entry(path: String): Entry? = entries.firstOrNull { it.path == path }

    // MARK: Réglages du moteur

    fun loadSettings() = fire("settings") { if (!it.has("error")) settings = it }

    fun setSetting(key: String, value: Any) {
        settings = JSONObject(settings.toString()).put(key, value)
        fire("settings", JSONObject().put("values", JSONObject().put(key, value))) { if (!it.has("error")) settings = it }
    }

    fun shutdown() = fire("shutdown")
}
