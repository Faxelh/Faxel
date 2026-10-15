package com.faxel.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.DeleteSweep
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.app.R
import com.faxel.app.data.Analysis
import com.faxel.app.data.Job
import com.faxel.app.data.Prefs
import com.faxel.app.engine.Engine
import java.io.File

const val BEST = "Meilleure"

/** État de l'écran (gardé quand on change d'onglet). */
object DownloadModel {
    var link by mutableStateOf("")
    var analyzing by mutableStateOf(false)
    var analysis by mutableStateOf<Analysis?>(null)
    var error by mutableStateOf<String?>(null)
    var media by mutableStateOf(Prefs.defaultMedia.value)
    var quality by mutableStateOf(Prefs.defaultQuality.value)
    var sent by mutableStateOf<Int?>(null)

    fun analyze(url: String, playlist: Boolean = false) {
        val clean = url.trim()
        if (clean.isBlank()) return
        link = clean
        analyzing = true
        analysis = null
        error = null
        sent = null
        Engine.analyze(clean, playlist) { info, message ->
            if (link != clean) return@analyze
            analyzing = false
            analysis = info
            error = message
            if (info != null) {
                if (!info.videoOk) media = "audio"
                if (!info.audioOk) media = "video"
                if (quality != BEST && quality !in info.qualities) quality = BEST
            }
        }
    }

    fun download(info: Analysis) {
        val items = if (info.isPlaylist && info.entries.isNotEmpty()) info.entries.map { Triple(it.first, it.second, null as String?) }
        else listOf(Triple(info.url.ifBlank { link }, info.title, null as String?))
        Engine.download(items, media, if (media == "audio") BEST else quality) { count ->
            sent = count
            analysis = null
            link = ""
        }
    }

    fun clear() {
        link = ""
        analysis = null
        error = null
        analyzing = false
        sent = null
    }
}

@Composable
fun DownloadScreen(onSearch: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val model = DownloadModel

    LaunchedEffect(Engine.pendingLink, Engine.ready) {
        val link = Engine.pendingLink ?: return@LaunchedEffect
        if (!Engine.ready) return@LaunchedEffect
        Engine.pendingLink = null
        if (Engine.pendingAutoDownload) {
            Engine.pendingAutoDownload = false
            model.link = link
            Engine.downloadText(link, Prefs.defaultMedia.value, Prefs.defaultQuality.value) { model.sent = it; model.link = "" }
        } else {
            model.analyze(link)
        }
    }

    val top: LazyListScope.() -> Unit = {
        item { ScreenTitle(stringResource(R.string.tab_download)) { IconButton(onClick = onSearch) { Icon(Icons.Rounded.Search, null, tint = accent) } } }
        item { EngineStatus() }
        item { LinkCard(onPaste = { clipboard.getText()?.text ?: "" }) }
        model.sent?.let { count ->
            item {
                Text(
                    stringResource(R.string.added_to_queue, count), color = accent, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                )
            }
        }
        if (model.analyzing) item { AnalyzingCard() }
        model.error?.let { item { ErrorCard(it) } }
        model.analysis?.let { item { AnalysisCard(it) } }
    }
    val jobs: LazyListScope.() -> Unit = { jobsSection() }

    if (Layout.wide) {
        Row(Modifier.fillMaxSize()) {
            LazyColumn(Modifier.weight(1f).fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp), content = top)
            LazyColumn(Modifier.weight(1f).fillMaxSize(), contentPadding = PaddingValues(top = 60.dp, bottom = 24.dp), content = jobs)
        }
    } else {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            top()
            jobs()
        }
    }
}

@Composable
private fun EngineStatus() {
    val error = Engine.startError
    if (Engine.ready && error == null) return
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (error == null) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.engine_starting), color = Muted)
            } else {
                Text(stringResource(R.string.engine_error) + "\n" + error, color = Color(0xFFFF6B6B), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun LinkCard(onPaste: () -> String) {
    val model = DownloadModel
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
        OutlinedTextField(
            value = model.link,
            onValueChange = { model.link = it },
            singleLine = true,
            placeholder = { Text(stringResource(R.string.link_hint)) },
            trailingIcon = {
                if (model.link.isNotEmpty()) IconButton(onClick = { model.clear() }) { Icon(Icons.Rounded.Close, null) }
                else IconButton(onClick = { model.link = onPaste().trim() }) { Icon(Icons.Rounded.ContentPaste, null) }
            },
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Surface1, focusedContainerColor = Surface1),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // Un seul geste : coller le lien et lancer l'import avec les réglages par défaut.
            Box(
                Modifier
                    .weight(1f)
                    .height(52.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Brush.horizontalGradient(listOf(accent, Color(0xFFFF2D60))))
                    .clickable(enabled = Engine.ready) {
                        val text = model.link.ifBlank { onPaste() }
                        if (text.isNotBlank()) {
                            Engine.downloadText(text, model.media, model.quality) { count -> model.sent = count; model.link = "" }
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Download, null, tint = Color.White)
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.paste_download), color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1)
                }
            }
            OutlinedButton(
                onClick = { model.analyze(model.link.ifBlank { onPaste() }) },
                enabled = Engine.ready && !model.analyzing,
                modifier = Modifier.height(52.dp),
                shape = RoundedCornerShape(16.dp),
            ) { Text(stringResource(R.string.analyze)) }
        }
        Spacer(Modifier.height(10.dp))
        MediaChoice(null)
    }
}

/** Vidéo / Audio et qualité. */
@Composable
private fun MediaChoice(info: Analysis?) {
    val model = DownloadModel
    Column {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (info == null || info.videoOk) Chip(stringResource(R.string.video), model.media == "video") { model.media = "video"; Prefs.defaultMedia.value = "video" }
            if (info == null || info.audioOk) Chip(stringResource(R.string.audio), model.media == "audio") { model.media = "audio"; Prefs.defaultMedia.value = "audio" }
        }
        if (model.media == "video") {
            Spacer(Modifier.height(8.dp))
            val qualities = listOf(BEST) + (info?.qualities?.filter { it != BEST } ?: listOf("1080p", "720p", "480p", "360p"))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                qualities.forEach { q ->
                    Chip(if (q == BEST) stringResource(R.string.best) else q, model.quality == q) {
                        model.quality = q
                        Prefs.defaultQuality.value = q
                    }
                }
            }
        }
    }
}

@Composable
private fun AnalyzingCard() {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(12.dp))
            Text(stringResource(R.string.analyzing), color = Color.White)
        }
    }
}

@Composable
private fun ErrorCard(message: String) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Column {
            Text(stringResource(R.string.analyze_failed), color = Color(0xFFFF6B6B), fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text(message, color = Muted, fontSize = 14.sp)
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { DownloadModel.analyze(DownloadModel.link) }) {
                Icon(Icons.Rounded.Refresh, null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.retry))
            }
        }
    }
}

@Composable
private fun AnalysisCard(info: Analysis) {
    val model = DownloadModel
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Column {
            Row {
                Thumb(info.thumbnail, null, modifier = Modifier.width(132.dp).aspectRatio(16f / 9f))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(info.title.ifBlank { info.url }, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 3, overflow = TextOverflow.Ellipsis)
                    val details = listOfNotNull(
                        info.platformName.ifBlank { null },
                        info.uploader.ifBlank { null },
                        info.duration?.takeIf { it > 0 }?.let { formatTime(it) },
                        if (info.isPlaylist) stringResource(R.string.n_videos, info.entries.size) else null,
                        if (info.photoCount > 0) stringResource(R.string.n_photos, info.photoCount) else null,
                    ).joinToString(" · ")
                    Text(details, color = Muted, fontSize = 13.sp, maxLines = 2)
                }
            }
            Spacer(Modifier.height(12.dp))
            if (!info.isPhoto) MediaChoice(info)
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { model.download(info) },
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(14.dp),
            ) {
                Icon(Icons.Rounded.Download, null)
                Spacer(Modifier.width(6.dp))
                Text(
                    if (info.isPlaylist) stringResource(R.string.download_all, info.entries.size) else stringResource(R.string.download),
                    fontWeight = FontWeight.Bold,
                )
            }
            // Vidéo regardée dans une playlist : on peut aussi prendre la playlist entière.
            if (!info.isPlaylist && info.playlistUrl.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = { model.analyze(info.playlistUrl, playlist = true) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                ) {
                    Icon(Icons.Rounded.PlaylistPlay, null)
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.whole_playlist))
                }
            }
            if (info.isPlaylist) {
                Spacer(Modifier.height(8.dp))
                info.entries.take(50).forEachIndexed { i, (_, title) ->
                    Text("${i + 1}. $title", color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(vertical = 2.dp))
                }
                if (info.entries.size > 50) Text("…", color = Muted)
            }
        }
    }
}

// MARK: Imports

private fun LazyListScope.jobsSection() {
    val jobs = Engine.jobs
    item {
        Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            SectionTitle(stringResource(R.string.downloads), Modifier.weight(1f))
            if (jobs.any { it.active }) {
                IconButton(onClick = { Engine.job("pause_all") }) { Icon(Icons.Rounded.Pause, null, tint = Muted) }
            }
            if (jobs.any { it.paused }) {
                IconButton(onClick = { Engine.job("resume_all") }) { Icon(Icons.Rounded.PlayArrow, null, tint = Muted) }
            }
            if (jobs.any { !it.active && !it.paused }) {
                IconButton(onClick = { Engine.job("clear_finished") }) { Icon(Icons.Rounded.DeleteSweep, null, tint = Muted) }
            }
        }
    }
    if (jobs.isEmpty()) {
        item { EmptyState(stringResource(R.string.no_downloads), stringResource(R.string.no_downloads_hint), Icons.Rounded.Download) }
    }
    items(jobs, key = { it.id }) { job -> JobRow(job) }
}

@Composable
private fun JobRow(job: Job) {
    val context = LocalContext.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = job.filepath.isNotBlank() && File(job.filepath).exists()) {
                val entry = Engine.entry(job.filepath)
                if (entry != null) openEntry(context, entry, listOf(entry)) {}
            }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Thumb(job.thumbnail, job.filepath.ifBlank { null }, modifier = Modifier.width(96.dp).aspectRatio(16f / 9f), audio = job.mediaType == "audio")
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(job.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val status = buildList {
                add(job.label.ifBlank { job.status })
                if (job.active) {
                    job.speed?.takeIf { it > 0 }?.let { add(formatSize(it) + "/s") }
                    job.eta?.takeIf { it > 0 }?.let { add(formatTime(it)) }
                }
                if (job.platformName.isNotBlank()) add(job.platformName)
            }.joinToString(" · ")
            Text(status, color = if (job.failed) Color(0xFFFF6B6B) else Muted, fontSize = 12.sp, maxLines = 1)
            if (job.failed && job.message.isNotBlank()) {
                Text(job.message, color = Muted, fontSize = 12.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            if (job.active || job.paused) {
                Spacer(Modifier.height(6.dp))
                if (job.fraction > 0) {
                    LinearProgressIndicator(progress = { job.fraction.toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        }
        when {
            job.active -> {
                IconButton(onClick = { Engine.job("pause", job.id) }) { Icon(Icons.Rounded.Pause, null, tint = Muted) }
                IconButton(onClick = { Engine.job("cancel", job.id) }) { Icon(Icons.Rounded.Close, null, tint = Muted) }
            }
            job.paused -> {
                IconButton(onClick = { Engine.job("resume", job.id) }) { Icon(Icons.Rounded.PlayArrow, null, tint = Muted) }
                IconButton(onClick = { Engine.job("cancel", job.id) }) { Icon(Icons.Rounded.Close, null, tint = Muted) }
            }
            job.failed -> IconButton(onClick = { Engine.job("retry", job.id) }) { Icon(Icons.Rounded.Refresh, null, tint = accent) }
        }
    }
}
