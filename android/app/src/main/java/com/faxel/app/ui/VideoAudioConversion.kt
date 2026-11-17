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
import java.nio.ByteBuffer

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
