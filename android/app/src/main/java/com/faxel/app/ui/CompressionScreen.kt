package com.faxel.app.ui

import android.content.Context
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.activity.compose.BackHandler
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.effect.Presentation
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import com.faxel.app.R
import com.faxel.app.data.Entry
import com.faxel.app.engine.Engine
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

private data class CompressQuality(val label: String, val shortSide: Int, val bitrate: Int, val estimate: Float)
private val compressQualities = listOf(
    CompressQuality("1080p", 1080, 5_000_000, 0.62f),
    CompressQuality("720p", 720, 2_500_000, 0.38f),
    CompressQuality("480p", 480, 1_000_000, 0.22f),
    CompressQuality("360p", 360, 600_000, 0.15f),
)

@OptIn(UnstableApi::class)
@Composable
fun CompressionScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf<Entry?>(null) }
    var sourceTab by remember { mutableStateOf(0) }
    var photoSource by remember { mutableStateOf(false) }
    var sourceSize by remember { mutableStateOf(0L) }
    var gallerySaveAttempted by remember { mutableStateOf(false) }
    val videos = if (sourceTab == 0) listOfNotNull(selected).filter { photoSource }
        else Engine.entries.filter { it.isVideo && it.exists }
    var savedToGallery by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val picked = withContext(Dispatchers.IO) { copyPickedVideo(context, uri) }
            selected = picked
            photoSource = picked != null
            picked?.let { sourceSize = File(it.path).length() }
        }
    }
    var quality by remember { mutableStateOf(compressQualities[1]) }
    var transformer by remember { mutableStateOf<Transformer?>(null) }
    var running by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }
    var output by remember { mutableStateOf<File?>(null) }
    var activeOutput by remember { mutableStateOf<File?>(null) }
    var outputSize by remember { mutableStateOf(0L) }

    fun cancelCompression() {
        transformer?.cancel()
        activeOutput?.delete()
        activeOutput = null
        transformer = null
        running = false
    }

    BackHandler(enabled = true) {
        if (running) cancelCompression()
        onClose()
    }

    LaunchedEffect(running, transformer) {
        val current = transformer ?: return@LaunchedEffect
        val holder = ProgressHolder()
        while (running) {
            if (current.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                progress = holder.progress / 100f
            }
            delay(250)
        }
    }

    Column(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { if (!running) onClose() }, enabled = !running) { Icon(Icons.Rounded.ArrowBack, null, tint = Color.White) }
            Text(stringResource(R.string.home_compress), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (running) IconButton(onClick = { cancelCompression(); onClose() }) { Icon(Icons.Rounded.Close, null, tint = Color.White) }
        }

        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("Photos", sourceTab == 0) { sourceTab = 0; if (!photoSource) selected = null }
            Chip("Vidéos de l'app", sourceTab == 1) { sourceTab = 1; if (photoSource) { selected = null; photoSource = false } }
        }

        if (output == null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                compressQualities.forEach { option ->
                    Chip(option.label, quality == option) { quality = option }
                }
            }
            if (sourceTab == 0) {
                OutlinedButton(onClick = { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)) },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    Icon(Icons.Rounded.VideoLibrary, null); Spacer(Modifier.size(8.dp)); Text("Choisir une vidéo dans Photos")
                }
                Text("Sélectionnez une vidéo de votre galerie pour la compresser.", color = Muted, fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            }
            Text(if (sourceTab == 0) "Votre vidéo sélectionnée" else "Choisissez une vidéo", color = Muted, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
            val picked = selected?.takeIf { sourceTab == 1 || photoSource }
            if (picked != null) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Taille estimée : ${formatSize((sourceSize * quality.estimate).toDouble())}", color = Muted, fontSize = 13.sp)
                    if (running) {
                        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth(), color = accent)
                        Text("Compression… ${(progress * 100).toInt()} %", color = Muted, fontSize = 12.sp)
                    } else {
                        Button(onClick = {
                            savedToGallery = false
                            gallerySaveAttempted = false
                            startCompression(context, picked, quality,
                                onStart = { job, file -> transformer = job; activeOutput = file; output = null; error = null; running = true },
                                onDone = { file -> output = file; outputSize = file.length(); activeOutput = null; if (!photoSource) Engine.rescan(); running = false; transformer = null },
                                reportError = { message -> activeOutput?.delete(); activeOutput = null; error = message; running = false; transformer = null })
                        }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = accent)) {
                            Icon(Icons.Rounded.VideoLibrary, null); Spacer(Modifier.size(8.dp)); Text("Compresser")
                        }
                    }
                    error?.let { Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp) }
                }
            }
            if (videos.isEmpty()) {
                if (sourceTab == 1) EmptyState(stringResource(R.string.no_videos), stringResource(R.string.no_videos_hint))
                else Text("Aucune vidéo sélectionnée.", color = Muted, modifier = Modifier.padding(16.dp))
            } else {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(videos, key = { it.path }) { entry ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 14.dp).clip(RoundedCornerShape(14.dp))
                                .background(if (entry.path == selected?.path) Surface2 else Surface1)
                                .clickable(enabled = !running) { selected = entry; photoSource = sourceTab == 0; sourceSize = File(entry.path).length() }
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Thumb(entry.thumbnail, entry.path, modifier = Modifier.size(width = 86.dp, height = 58.dp).clip(RoundedCornerShape(9.dp)))
                            Column(Modifier.weight(1f).padding(start = 11.dp)) {
                                Text(entry.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                Text(formatSize(File(entry.path).length().toDouble()), color = Muted, fontSize = 12.sp)
                            }
                            if (entry.path == selected?.path) Icon(Icons.Rounded.CheckCircle, null, tint = accent, modifier = Modifier.size(22.dp))
                        }
                    }
                }
            }
        } else {
            Column(Modifier.weight(1f).fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Compression terminée", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("Nouvelle taille : ${formatSize(outputSize.toDouble())}", color = Muted)
                val gain = if (sourceSize > 0) (100 - outputSize * 100 / sourceSize).toInt() else 0
                Text("Gain : ${gain.coerceAtLeast(0)} %", color = accent, fontWeight = FontWeight.SemiBold)
                Text("L’original est conservé. La copie compressée est enregistrée à côté de la vidéo.", color = Muted)
                if (photoSource) {
                    Button(onClick = { gallerySaveAttempted = true; output?.let { file -> scope.launch { savedToGallery = withContext(Dispatchers.IO) { saveVideoToGallery(context, file) } } } },
                        colors = ButtonDefaults.buttonColors(containerColor = accent)) {
                        Text(if (savedToGallery) "Enregistrée dans Photos" else "Enregistrer dans Photos")
                    }
                    if (gallerySaveAttempted && !savedToGallery) Text("Impossible d'enregistrer dans Photos.", color = Color(0xFFFF6B6B))
                }
                Button(onClick = onClose, colors = ButtonDefaults.buttonColors(containerColor = accent)) { Text("Terminé") }
            }
        }
    }
}

@OptIn(UnstableApi::class)
private fun startCompression(
    context: Context,
    entry: Entry,
    quality: CompressQuality,
    onStart: (Transformer, File) -> Unit,
    onDone: (File) -> Unit,
    reportError: (String) -> Unit,
) {
    val input = File(entry.path)
    if (!input.isFile) { reportError("Vidéo introuvable."); return }
    val stem = input.nameWithoutExtension + " (compressée)"
    var destination = File(input.parentFile, "$stem.mp4")
    var suffix = 2
    while (destination.exists()) destination = File(input.parentFile, "$stem ${suffix++}.mp4")
    try {
        val encoderFactory = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(quality.bitrate).build())
            .build()
        val built = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: androidx.media3.transformer.Composition, result: ExportResult) {
                    onDone(destination)
                }
                override fun onError(composition: androidx.media3.transformer.Composition, result: ExportResult, exception: ExportException) {
                    destination.delete()
                    reportError(exception.localizedMessage ?: "La compression a échoué.")
                }
            })
            .build()
        val effects = Effects(emptyList(), listOf<Effect>(Presentation.createForHeight(quality.shortSide)))
        val edited = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input))).setEffects(effects).build()
        onStart(built, destination)
        built.start(edited, destination.absolutePath)
    } catch (failure: Exception) {
        destination.delete()
        reportError(failure.localizedMessage ?: "Impossible de compresser cette vidéo.")
    }
}

private fun copyPickedVideo(context: Context, uri: Uri): Entry? = runCatching {
    val directory = File(context.cacheDir, "FaxelCompression").apply { mkdirs() }
    val output = File(directory, "source-${UUID.randomUUID()}.mp4")
    context.contentResolver.openInputStream(uri)?.use { input ->
        output.outputStream().use { stream -> input.copyTo(stream) }
    } ?: return null
    Entry(
        uid = "photo-${UUID.randomUUID()}", path = output.absolutePath,
        title = uri.lastPathSegment?.substringAfterLast('/')?.substringBefore('?')?.ifBlank { null } ?: "Vidéo de Photos",
        duration = null, filesize = output.length().toDouble(), thumbnail = null, date = "", uploader = "",
        platformName = "Photos", sourceUrl = uri.toString(), mediaType = "video", isFolder = false, exists = true,
    )
}.getOrNull()

private fun saveVideoToGallery(context: Context, file: File): Boolean = runCatching {
    val resolver = context.contentResolver
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/Faxel")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        try {
            resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } }
                ?: throw IllegalStateException("Impossible d'ouvrir la galerie")
            values.clear(); values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    } else {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: return false
        val copy = File(directory, file.name)
        file.copyTo(copy, overwrite = true)
        android.media.MediaScannerConnection.scanFile(context, arrayOf(copy.absolutePath), arrayOf("video/mp4"), null)
    }
    true
}.getOrDefault(false)
