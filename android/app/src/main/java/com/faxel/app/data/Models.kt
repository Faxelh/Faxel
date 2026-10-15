package com.faxel.app.data

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

fun JSONObject.str(key: String): String = if (isNull(key)) "" else optString(key, "")
fun JSONObject.num(key: String): Double? = if (isNull(key) || !has(key)) null else optDouble(key).takeIf { !it.isNaN() }
fun JSONObject.flag(key: String): Boolean = when (val v = opt(key)) {
    is Boolean -> v
    is Number -> v.toInt() != 0
    is String -> v == "true" || v == "1"
    else -> false
}

fun JSONArray?.objects(): List<JSONObject> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optJSONObject(it) }
}

val AUDIO_EXT = setOf("m4a", "mp3", "aac", "wav", "flac", "ogg", "opus", "aif", "aiff", "m4b", "wma")
val VIDEO_EXT = setOf("mp4", "mov", "m4v", "3gp", "mkv", "webm", "avi", "ts")

/** Un élément de la bibliothèque (vidéo, son ou dossier de photos). */
data class Entry(
    val uid: String,
    val path: String,
    val title: String,
    val duration: Double?,
    val filesize: Double?,
    val thumbnail: String?,
    val date: String,
    val uploader: String,
    val platformName: String,
    val sourceUrl: String,
    val mediaType: String,
    val isFolder: Boolean,
    val exists: Boolean,
) {
    val isAudio: Boolean get() = mediaType == "audio" || File(path).extension.lowercase() in AUDIO_EXT
    val isVideo: Boolean get() = !isFolder && !isAudio
    val folder: String get() = File(path).parentFile?.name ?: ""
    val folderPath: String get() = File(path).parent ?: ""
    val key: String get() = uid.ifBlank { path }

    companion object {
        fun from(o: JSONObject): Entry {
            val path = o.str("filepath")
            val file = File(path)
            return Entry(
                uid = o.str("uid"),
                path = path,
                title = o.str("title").ifBlank { file.nameWithoutExtension },
                duration = o.num("duration"),
                filesize = o.num("filesize"),
                thumbnail = o.str("thumbnail").ifBlank { null },
                date = o.str("date"),
                uploader = o.str("uploader"),
                platformName = o.str("platform_name"),
                sourceUrl = o.str("url"),
                mediaType = o.str("media_type").ifBlank { if (file.extension.lowercase() in AUDIO_EXT) "audio" else "video" },
                isFolder = if (o.has("is_folder")) o.flag("is_folder") else file.isDirectory,
                exists = if (o.has("exists")) o.flag("exists") else file.exists(),
            )
        }
    }
}

data class Playlist(val id: String, val name: String, val paths: List<String>) {
    companion object {
        fun from(o: JSONObject) = Playlist(
            o.str("uid"), o.str("name").ifBlank { "Playlist" },
            o.optJSONArray("items").objects().map { it.str("filepath") }.filter { it.isNotBlank() },
        )
    }
}

/** Un import en cours ou terminé. */
data class Job(
    val id: String,
    val url: String,
    val title: String,
    val status: String,
    val label: String,
    val fraction: Double,
    val speed: Double?,
    val eta: Double?,
    val message: String,
    val thumbnail: String?,
    val active: Boolean,
    val mediaType: String,
    val quality: String,
    val platformName: String,
    val filepath: String,
) {
    val failed: Boolean get() = status == "failed"
    val done: Boolean get() = status == "finished" || status == "done" || status == "completed"
    val paused: Boolean get() = status == "paused"

    companion object {
        fun from(o: JSONObject) = Job(
            id = o.str("id"),
            url = o.str("url"),
            title = o.str("title").ifBlank { o.str("url") },
            status = o.str("status"),
            label = o.str("label"),
            fraction = o.num("fraction") ?: 0.0,
            speed = o.num("speed"),
            eta = o.num("eta"),
            message = o.str("message"),
            thumbnail = o.str("thumbnail").ifBlank { null },
            active = o.flag("active"),
            mediaType = o.str("media_type").ifBlank { "video" },
            quality = o.str("quality"),
            platformName = o.str("platform_name"),
            filepath = o.str("filepath"),
        )
    }
}

/** Résultat de l'analyse d'un lien. */
data class Analysis(
    val kind: String,
    val url: String,
    val title: String,
    val uploader: String,
    val duration: Double?,
    val thumbnail: String?,
    val qualities: List<String>,
    val audioOk: Boolean,
    val videoOk: Boolean,
    val entries: List<Pair<String, String>>,
    val photoCount: Int,
    val platformName: String,
    val playlistUrl: String,
) {
    val isPlaylist: Boolean get() = kind == "playlist" || entries.size > 1
    val isPhoto: Boolean get() = kind == "photo" || photoCount > 0

    companion object {
        fun from(o: JSONObject): Analysis {
            val q = o.optJSONArray("qualities")
            return Analysis(
                kind = o.str("kind").ifBlank { "video" },
                url = o.str("url"),
                title = o.str("title"),
                uploader = o.str("uploader"),
                duration = o.num("duration"),
                thumbnail = o.str("thumbnail").ifBlank { null },
                qualities = if (q == null) emptyList() else (0 until q.length()).map { q.optString(it) }.filter { it.isNotBlank() },
                audioOk = if (o.has("audio_ok")) o.flag("audio_ok") else true,
                videoOk = if (o.has("video_ok")) o.flag("video_ok") else true,
                entries = o.optJSONArray("entries").objects().mapNotNull { e ->
                    val link = e.str("url")
                    if (link.isBlank()) null else link to e.str("title").ifBlank { link }
                },
                photoCount = (o.num("photo_count") ?: 0.0).toInt(),
                platformName = o.str("platform_name"),
                playlistUrl = o.str("playlist_url"),
            )
        }
    }
}

data class SearchResult(val url: String, val title: String, val uploader: String, val duration: Double?, val thumbnail: String?) {
    companion object {
        fun from(o: JSONObject) = SearchResult(
            o.str("url").ifBlank { o.str("webpage_url") }, o.str("title"), o.str("uploader").ifBlank { o.str("channel") },
            o.num("duration"), o.str("thumbnail").ifBlank { null },
        )
    }
}
