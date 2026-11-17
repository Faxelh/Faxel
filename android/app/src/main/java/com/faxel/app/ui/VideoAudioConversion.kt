package com.faxel.app.ui

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.app.data.Entry
import com.faxel.app.engine.Engine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AudioEdit(entry: Entry, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val duration = remember(entry.path) { readAudioDurationSeconds(entry.path).coerceAtLeast(1f) }
    var removePart by remember(entry.path) { mutableStateOf(false) }
    var start by remember(entry.path) { mutableStateOf(0f) }
    var end by remember(entry.path) { mutableStateOf(duration) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<File?>(null) }

    ModalBottomSheet(onDismissRequest = { if (!working) onClose() }, containerColor = Color(0xFF17171B)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Modifier l'audio", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text(entry.title, color = Color.LightGray, fontSize = 14.sp)
            Text("L'original reste intact. Le montage sans perte accepte les fichiers MP3 et AAC/M4A.", color = accent, fontSize = 13.sp)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(if (removePart) "Supprimer la partie" else "Garder seulement l'extrait", color = Color.White)
                Switch(checked = removePart, onCheckedChange = { removePart = it })
            }
            Text(if (removePart) "La plage sera retirée, puis les deux parties restantes seront réunies." else "Seule la plage choisie sera exportée dans un nouveau fichier.", color = Color.LightGray, fontSize = 13.sp)
            Text("Début : ${clock(start)}", color = Color.LightGray)
            Slider(value = start, onValueChange = { start = it.coerceAtMost(end - 0.25f) }, valueRange = 0f..(duration - 0.25f).coerceAtLeast(0.25f))
            Text("Fin : ${clock(end)}", color = Color.LightGray)
            Slider(value = end, onValueChange = { end = it.coerceAtLeast(start + 0.25f) }, valueRange = (start + 0.25f).coerceAtMost(duration)..duration)
            error?.let { Text(it, color = Color(0xFFFF7373), fontSize = 13.sp) }
            result?.let { Text("Fichier créé : ${it.name}", color = Color(0xFF7BE0A3), fontSize = 13.sp) }
            if (working) LinearProgressIndicator(Modifier.fillMaxWidth(), color = accent)
            Button(
                onClick = {
                    working = true
                    error = null
                    scope.launch {
                        val edited = withContext(Dispatchers.IO) {
                            editAudioFile(entry.path, (start * 1_000_000f).toLong(), (end * 1_000_000f).toLong(), removePart)
                        }
                        working = false
                        edited.onSuccess { file -> result = file; Engine.rescan() }
                            .onFailure { error = it.localizedMessage ?: "La modification audio a échoué." }
                    }
                },
                enabled = !working && end > start && (!removePart || duration - (end - start) > 0.25f),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (working) "Modification…" else if (removePart) "Supprimer cette partie" else "Créer l'extrait") }
            TextButton(onClick = onClose, enabled = !working, modifier = Modifier.fillMaxWidth()) { Text("Fermer", color = Color.LightGray) }
            Spacer(Modifier.height(16.dp))
        }
    }
}

private fun readAudioDurationSeconds(path: String): Float = runCatching {
    val extractor = MediaExtractor()
    try {
        extractor.setDataSource(path)
        (0 until extractor.trackCount).firstNotNullOfOrNull { index ->
            val format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true && format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION) / 1_000_000f
            } else null
        } ?: 1f
    } finally { extractor.release() }
}.getOrDefault(1f).coerceAtLeast(1f)

private fun editAudioFile(path: String, startUs: Long, endUs: Long, removePart: Boolean): Result<File> = runCatching {
    val input = File(path)
    require(input.isFile) { "Fichier audio introuvable." }
    val extractor = MediaExtractor()
    var muxer: MediaMuxer? = null
    var mp3Output: FileOutputStream? = null
    var started = false
    val output = uniqueEditedAudioFile(input, removePart)
    try {
        extractor.setDataSource(input.absolutePath)
        val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: error("Aucune piste audio dans ce fichier.")
        val format = extractor.getTrackFormat(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)
        require(mime == "audio/mp4a-latm" || mime == "audio/mpeg") {
            "Sur Android, le montage sans perte accepte les fichiers MP3 et AAC/M4A."
        }
        val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else endUs
        val cutEnd = minOf(endUs, durationUs)
        require(startUs >= 0 && cutEnd > startUs && cutEnd - startUs >= 250_000L) { "La plage audio sélectionnée n'est pas valide." }
        require(!removePart || durationUs - (cutEnd - startUs) >= 250_000L) { "Il faut conserver au moins une partie du fichier." }
        val outputTrack = if (mime == "audio/mp4a-latm") {
            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer.addTrack(format).also { muxer.start(); started = true }
        } else {
            mp3Output = FileOutputStream(output)
            -1
        }
        extractor.selectTrack(trackIndex)
        val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
        val info = MediaCodec.BufferInfo()
        while (true) {
            info.offset = 0
            info.size = extractor.readSampleData(buffer, 0)
            if (info.size < 0) break
            val time = extractor.sampleTime
            val keep = if (removePart) time < startUs || time >= cutEnd else time >= startUs && time < cutEnd
            if (keep) {
                if (mime == "audio/mpeg") {
                    val bytes = ByteArray(info.size)
                    buffer.position(info.offset)
                    buffer.get(bytes, 0, info.size)
                    mp3Output?.write(bytes)
                } else {
                    info.presentationTimeUs = when {
                        !removePart -> time - startUs
                        time >= cutEnd -> time - (cutEnd - startUs)
                        else -> time
                    }.coerceAtLeast(0L)
                    info.flags = extractor.sampleFlags
                    muxer?.writeSampleData(outputTrack, buffer, info)
                }
            }
            if (!extractor.advance()) break
        }
        mp3Output?.flush()
        if (started) { muxer?.stop(); started = false }
        require(output.isFile && output.length() > 0) { "Aucun son n'a été exporté." }
        output
    } catch (failure: Throwable) {
        output.delete()
        throw failure
    } finally {
        if (started) runCatching { muxer?.stop() }
        muxer?.release()
        mp3Output?.close()
        extractor.release()
    }
}

private fun uniqueEditedAudioFile(input: File, removePart: Boolean): File {
    val parent = input.parentFile ?: input.absoluteFile.parentFile ?: error("Dossier de destination introuvable.")
    val base = "${input.nameWithoutExtension} (${if (removePart) "audio modifié" else "extrait"})"
    val extension = if (input.extension.equals("mp3", ignoreCase = true)) "mp3" else "m4a"
    var file = File(parent, "$base.$extension")
    var suffix = 2
    while (file.exists()) file = File(parent, "$base ${suffix++}.$extension")
    return file
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoAudioConversion(entry: Entry, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val duration = remember(entry.path) { readDurationSeconds(entry.path).coerceAtLeast(1f) }
    var whole by remember(entry.path) { mutableStateOf(true) }
    var start by remember(entry.path) { mutableStateOf(0f) }
    var end by remember(entry.path) { mutableStateOf(duration) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<File?>(null) }

    ModalBottomSheet(onDismissRequest = { if (!working) onClose() }, containerColor = Color(0xFF17171B)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Convertir en audio", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text(entry.title, color = Color.LightGray, fontSize = 14.sp)
            Text("Sortie : M4A (AAC, audio MP4)", color = accent, fontSize = 13.sp)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Toute la vidéo", color = Color.White)
                Switch(checked = whole, onCheckedChange = { whole = it })
            }
            if (!whole) {
                Text("Début : ${clock(start)}", color = Color.LightGray)
                Slider(value = start, onValueChange = { start = it.coerceAtMost(end - 0.25f) }, valueRange = 0f..(duration - 0.25f).coerceAtLeast(0.25f))
                Text("Fin : ${clock(end)}", color = Color.LightGray)
                Slider(value = end, onValueChange = { end = it.coerceAtLeast(start + 0.25f) }, valueRange = (start + 0.25f).coerceAtMost(duration)..duration)
            }
            error?.let { Text(it, color = Color(0xFFFF7373), fontSize = 13.sp) }
            result?.let { Text("Audio créé : ${it.name}", color = Color(0xFF7BE0A3), fontSize = 13.sp) }
            if (working) LinearProgressIndicator(Modifier.fillMaxWidth(), color = accent)
            Button(
                onClick = {
                    working = true
                    error = null
                    scope.launch {
                        val converted = withContext(Dispatchers.IO) {
                            extractAudio(entry.path, start.toLong() * 1_000_000L, if (whole) Long.MAX_VALUE else end.toLong() * 1_000_000L)
                        }
                        working = false
                        converted.onSuccess { file -> result = file; Engine.rescan() }
                            .onFailure { error = it.localizedMessage ?: "La conversion a échoué." }
                    }
                },
                enabled = !working && (whole || end > start),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (working) "Conversion…" else if (result == null) "Convertir" else "Recommencer") }
            TextButton(onClick = onClose, enabled = !working, modifier = Modifier.fillMaxWidth()) { Text("Fermer", color = Color.LightGray) }
            Spacer(Modifier.height(16.dp))
        }
    }
}

private fun readDurationSeconds(path: String): Float = runCatching {
    val extractor = MediaExtractor()
    try {
        extractor.setDataSource(path)
        (0 until extractor.trackCount).firstNotNullOfOrNull { index ->
            val format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true && format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION) / 1_000_000f
            } else null
        } ?: 1f
    } finally { extractor.release() }
}.getOrDefault(1f).coerceAtLeast(1f)

private fun extractAudio(path: String, startUs: Long, requestedEndUs: Long): Result<File> = runCatching {
    val input = File(path)
    require(input.isFile) { "Vidéo introuvable." }
    val extractor = MediaExtractor()
    var muxer: MediaMuxer? = null
    var started = false
    val output = uniqueAudioFile(input)
    try {
        extractor.setDataSource(input.absolutePath)
        val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: error("Aucune piste audio dans cette vidéo.")
        val format = extractor.getTrackFormat(trackIndex)
        require(format.getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm") {
            "Cette vidéo utilise un codec audio qui ne peut pas être copié sans réencodage."
        }
        val actualEnd = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else requestedEndUs
        val endUs = minOf(requestedEndUs, actualEnd)
        require(endUs > startUs) { "La durée de coupe est invalide." }
        muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val outputTrack = muxer.addTrack(format)
        muxer.start(); started = true
        extractor.selectTrack(trackIndex)
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
        val info = MediaCodec.BufferInfo()
        while (true) {
            info.offset = 0
            info.size = extractor.readSampleData(buffer, 0)
            if (info.size < 0) break
            val time = extractor.sampleTime
            if (time > endUs) break
            if (time >= startUs) {
                info.presentationTimeUs = time - startUs
                info.flags = extractor.sampleFlags
                muxer.writeSampleData(outputTrack, buffer, info)
            }
            if (!extractor.advance()) break
        }
        muxer.stop(); started = false
        require(output.isFile && output.length() > 0) { "Aucun son n'a pu être extrait." }
        output
    } catch (failure: Throwable) {
        output.delete()
        throw failure
    } finally {
        if (started) runCatching { muxer?.stop() }
        muxer?.release()
        extractor.release()
    }
}

private fun uniqueAudioFile(input: File): File {
    val parent = input.parentFile ?: input.absoluteFile.parentFile ?: error("Dossier de destination introuvable.")
    val base = "${input.nameWithoutExtension} (audio)"
    var file = File(parent, "$base.m4a")
    var suffix = 2
    while (file.exists()) file = File(parent, "$base ${suffix++}.m4a")
    return file
}

private fun clock(seconds: Float): String {
    val total = seconds.toInt().coerceAtLeast(0)
    return "%02d:%02d".format(total / 60, total % 60)
}
