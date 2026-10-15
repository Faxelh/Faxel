package com.faxel.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import org.json.JSONArray
import org.json.JSONObject

class StringPref(private val key: String, default: String) {
    private val state = mutableStateOf(default)
    var value: String
        get() = state.value
        set(v) {
            state.value = v
            Prefs.prefs.edit().putString(key, v).apply()
        }

    fun load(p: SharedPreferences) {
        state.value = p.getString(key, state.value) ?: state.value
    }
}

class BoolPref(private val key: String, default: Boolean) {
    private val state = mutableStateOf(default)
    var value: Boolean
        get() = state.value
        set(v) {
            state.value = v
            Prefs.prefs.edit().putBoolean(key, v).apply()
        }

    fun load(p: SharedPreferences) {
        state.value = p.getBoolean(key, state.value)
    }
}

data class WebLink(val url: String, val title: String)

/** Réglages de l'interface (ceux du moteur restent en Python : op_settings). */
object Prefs {
    lateinit var prefs: SharedPreferences

    val defaultMedia = StringPref("defaultMedia", "video")
    val defaultQuality = StringPref("defaultQuality", "Meilleure")
    val accent = StringPref("accent", "7C5CFF")
    val askDownload = BoolPref("askDownload", true)
    val oneTapShare = BoolPref("oneTapShare", false)
    val autoSubtitles = BoolPref("autoSubtitles", true)
    val autoPip = BoolPref("autoPip", true)
    val askedStorage = BoolPref("askedStorage", false)
    val homePage = StringPref("homePage", "")
    val searchEngine = StringPref("searchEngine", "google")

    val bookmarks = mutableStateOf<List<WebLink>>(emptyList())
    val history = mutableStateOf<List<WebLink>>(emptyList())

    val accents = listOf("7C5CFF", "FF2D60", "FF9500", "FFCC00", "34C759", "00C7BE", "0A84FF", "BF5AF2", "FF375F")

    fun init(context: Context) {
        prefs = context.getSharedPreferences("faxel", Context.MODE_PRIVATE)
        listOf(defaultMedia, defaultQuality, accent, homePage, searchEngine).forEach { it.load(prefs) }
        listOf(askDownload, oneTapShare, autoSubtitles, autoPip, askedStorage).forEach { it.load(prefs) }
        bookmarks.value = readLinks("bookmarks")
        history.value = readLinks("history")
    }

    private fun readLinks(key: String): List<WebLink> = runCatching {
        JSONArray(prefs.getString(key, "[]")).objects().map { WebLink(it.str("url"), it.str("title")) }
    }.getOrDefault(emptyList())

    private fun writeLinks(key: String, links: List<WebLink>) {
        val array = JSONArray()
        links.forEach { array.put(JSONObject().put("url", it.url).put("title", it.title)) }
        prefs.edit().putString(key, array.toString()).apply()
    }

    fun isBookmarked(url: String) = bookmarks.value.any { it.url == url }

    fun toggleBookmark(url: String, title: String) {
        bookmarks.value = if (isBookmarked(url)) bookmarks.value.filter { it.url != url }
        else listOf(WebLink(url, title.ifBlank { url })) + bookmarks.value
        writeLinks("bookmarks", bookmarks.value)
    }

    fun removeBookmark(url: String) {
        bookmarks.value = bookmarks.value.filter { it.url != url }
        writeLinks("bookmarks", bookmarks.value)
    }

    fun visit(url: String, title: String) {
        if (url.startsWith("about:") || url.isBlank()) return
        history.value = (listOf(WebLink(url, title.ifBlank { url })) + history.value.filter { it.url != url }).take(300)
        writeLinks("history", history.value)
    }

    fun clearHistory() {
        history.value = emptyList()
        writeLinks("history", emptyList())
    }
}
