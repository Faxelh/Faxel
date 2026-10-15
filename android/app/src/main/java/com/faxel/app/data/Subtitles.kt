package com.faxel.app.data

import java.io.File
import java.util.Locale

/** Sous-titres trouvés tout seuls à côté d'une vidéo (films et séries). */
data class SubtitleFile(val file: File, val language: String?, val label: String, val forced: Boolean) {
    val mime: String
        get() = when (file.extension.lowercase()) {
            "vtt" -> "text/vtt"
            "ass", "ssa" -> "text/x-ssa"
            else -> "application/x-subrip"
        }
}

object Subtitles {
    val EXTENSIONS = setOf("srt", "vtt", "ass", "ssa")
    private val FOLDERS = setOf("subs", "sub", "subtitles", "subtitle", "sous-titres", "sous titres", "soustitres", "st", "srt", "vostfr")

    private val episodePatterns = listOf(
        Regex("""s(\d{1,2})[ ._-]?e(\d{1,3})"""),
        Regex("""(?<![0-9])(\d{1,2})x(\d{2,3})(?![0-9])"""),
        Regex("""saison[ ._-]?(\d{1,2}).*?[ée]pisode[ ._-]?(\d{1,3})"""),
        Regex("""season[ ._-]?(\d{1,2}).*?episode[ ._-]?(\d{1,3})"""),
    )

    fun episode(name: String): Pair<Int, Int>? {
        val lower = name.lowercase()
        for (regex in episodePatterns) {
            val match = regex.find(lower) ?: continue
            val season = match.groupValues[1].toIntOrNull() ?: continue
            val number = match.groupValues[2].toIntOrNull() ?: continue
            return season to number
        }
        return null
    }

    private val languages = listOf(
        "fr" to listOf("fr", "fre", "fra", "french", "francais", "français", "vf", "vff", "vfq", "vostfr", "truefrench"),
        "en" to listOf("en", "eng", "english", "anglais"),
        "es" to listOf("es", "spa", "esp", "spanish", "espanol", "español", "castellano", "latino"),
        "de" to listOf("de", "ger", "deu", "german", "deutsch", "allemand"),
        "ru" to listOf("ru", "rus", "russian", "русский"),
        "pt" to listOf("pt", "por", "portuguese", "portugues", "português", "br"),
        "it" to listOf("it", "ita", "italian", "italiano"),
        "ar" to listOf("ar", "ara", "arabic", "arabe"),
    )

    fun language(file: File): String? {
        val tokens = file.nameWithoutExtension.lowercase().split(Regex("""[^\p{L}]+""")).filter { it.isNotEmpty() }
        val words = tokens.filter { it.length > 3 }.toSet() + tokens.takeLast(3)
        return languages.firstOrNull { (_, keys) -> keys.any { it in words } }?.first
    }

    private fun describe(file: File): SubtitleFile {
        val lower = file.name.lowercase()
        val forced = "forced" in lower || "forcé" in lower
        val code = language(file)
        val name = if (code == null) file.name else {
            val display = Locale(code).getDisplayLanguage(Locale.getDefault()).replaceFirstChar { it.titlecase() }
            display + (if (forced) " (forced)" else "") + (if ("sdh" in lower) " (SDH)" else "")
        }
        return SubtitleFile(file, code, name, forced)
    }

    /** Sous-titres de la vidéo : même nom, même épisode, dossier « Subs »… (langue de l'app en premier). */
    fun find(video: File): List<SubtitleFile> {
        val folder = video.parentFile ?: return emptyList()
        val base = video.nameWithoutExtension.lowercase()
        val code = episode(base)
        val children = folder.listFiles()?.toList() ?: return emptyList()
        val videosHere = children.count { it.isFile && it.extension.lowercase() in VIDEO_EXT }
        val found = ArrayList<Pair<File, Boolean>>()

        fun consider(file: File, ownFolder: Boolean) {
            if (file.extension.lowercase() !in EXTENSIONS) return
            val stem = file.nameWithoutExtension.lowercase()
            if (stem == base || listOf(".", "_", " ", "-").any { stem.startsWith(base + it) }) {
                found += file to true
                return
            }
            if (code != null) {
                val other = episode(stem)
                if (other != null) {
                    if (other == code) found += file to true
                    return
                }
            }
            if (ownFolder || videosHere <= 1) found += file to false
        }

        for (child in children) {
            if (child.isFile) {
                consider(child, false)
                continue
            }
            val lower = child.name.lowercase()
            if (lower !in FOLDERS && lower != base) continue
            child.listFiles()?.forEach { inner ->
                if (inner.isDirectory) {
                    val innerName = inner.name.lowercase()
                    val same = code != null && episode(innerName) == code
                    if (innerName == base || same) inner.listFiles()?.forEach { consider(it, true) }
                } else {
                    consider(inner, lower == base || code == null)
                }
            }
        }
        val app = Locale.getDefault().language
        return found.distinctBy { it.first.absolutePath }
            .sortedWith(compareBy({ !it.second }, { describe(it.first).language != app }, { describe(it.first).forced }, { it.first.name }))
            .map { describe(it.first) }
    }

    /** Ordre naturel des épisodes : S01E02 avant S01E10, « 2 » avant « 10 ». */
    fun episodeOrder(a: File, b: File): Int {
        val ea = episode(a.name)
        val eb = episode(b.name)
        if (ea != null && eb != null && ea != eb) {
            return compareValuesBy(ea, eb, { it.first }, { it.second })
        }
        return naturalCompare(a.name.lowercase(), b.name.lowercase())
    }

    private fun naturalCompare(a: String, b: String): Int {
        val chunk = Regex("""\d+|\D+""")
        val pa = chunk.findAll(a).map { it.value }.toList()
        val pb = chunk.findAll(b).map { it.value }.toList()
        for (i in 0 until minOf(pa.size, pb.size)) {
            val x = pa[i]
            val y = pb[i]
            val result = if (x[0].isDigit() && y[0].isDigit()) {
                (x.toBigIntegerOrNull() ?: java.math.BigInteger.ZERO).compareTo(y.toBigIntegerOrNull() ?: java.math.BigInteger.ZERO)
            } else x.compareTo(y)
            if (result != 0) return result
        }
        return pa.size - pb.size
    }
}
