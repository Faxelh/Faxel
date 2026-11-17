package com.faxel.app.data

import android.content.Context
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.android.gms.tasks.Tasks
import java.io.File

/** Traduit les textes d'un fichier SRT en conservant les minutages. */
object SubtitleTranslator {
    val languages = listOf(
        "fr" to "Français", "en" to "English", "es" to "Español", "de" to "Deutsch",
        "it" to "Italiano", "pt" to "Português", "ru" to "Русский", "ar" to "العربية",
        "ja" to "日本語", "zh" to "中文", "ko" to "한국어", "nl" to "Nederlands",
    )

    fun translate(context: Context, source: File, sourceLanguage: String?, targetLanguage: String): File {
        require(source.isFile) { "Fichier de sous-titres introuvable." }
        val text = source.readText(Charsets.UTF_8).removePrefix("\uFEFF")
        val blocks = text.split(Regex("\\r?\\n\\s*\\r?\\n")).filter { it.isNotBlank() }
        val from = TranslateLanguage.fromLanguageTag(sourceLanguage ?: "en")
            ?: TranslateLanguage.ENGLISH
        val to = TranslateLanguage.fromLanguageTag(targetLanguage)
            ?: error("Langue cible non prise en charge.")
        require(from != to) { "Choisissez une langue différente de la langue source." }
        val translator = Translation.getClient(
            TranslatorOptions.Builder().setSourceLanguage(from).setTargetLanguage(to).build(),
        )
        try {
            Tasks.await(translator.downloadModelIfNeeded())
            val translated = blocks.mapNotNull { block ->
                val lines = block.lines()
                if (lines.firstOrNull()?.trim()?.startsWith("WEBVTT", ignoreCase = true) == true) return@mapNotNull null
                val timingIndex = lines.indexOfFirst { "-->" in it }
                if (timingIndex < 0 || timingIndex == lines.lastIndex) return@mapNotNull block.trim()
                val cueHead = lines.take(timingIndex + 1)
                val cueText = lines.drop(timingIndex + 1).joinToString(" ").trim()
                if (cueText.isEmpty()) block.trim()
                else cueHead.plus(Tasks.await(translator.translate(cueText))).joinToString("\n")
            }
            require(translated.isNotEmpty()) { "Aucun sous-titre exploitable n'a été trouvé." }
            val outputDir = File(context.filesDir, "translated_subtitles").apply { mkdirs() }
            val safeName = source.nameWithoutExtension.replace(Regex("[^\\p{L}\\p{N}._-]"), "_")
            val output = File(outputDir, "$safeName.$targetLanguage.srt")
            output.writeText(translated.mapIndexed { index, cue ->
                val lines = cue.lines()
                val timingIndex = lines.indexOfFirst { "-->" in it }
                if (timingIndex >= 0) (listOf((index + 1).toString()) + lines.drop(timingIndex)).joinToString("\n") else cue
            }.joinToString("\n\n") + "\n", Charsets.UTF_8)
            return output
        } finally {
            translator.close()
        }
    }
}
