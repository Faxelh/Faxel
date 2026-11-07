package com.faxel.app.ui

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ActivityInfo
import android.os.Build
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.ui.text.style.TextAlign
import com.faxel.app.playback.AudioFx
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.faxel.app.data.Prefs
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.faxel.app.MainActivity
import com.faxel.app.R
import com.faxel.app.playback.AudioConnection
import com.faxel.app.playback.VideoState
import kotlinx.coroutines.delay

// MARK: Musique

@Composable
private fun rememberAudioPosition(): Pair<Long, Long> {
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    val controller = AudioConnection.controller
    val playing = AudioConnection.isPlaying
    val current = AudioConnection.currentPath
    LaunchedEffect(controller, playing, current) {
        while (true) {
            val c = controller ?: break
            position = c.currentPosition.coerceAtLeast(0)
            duration = c.duration.coerceAtLeast(0)
            if (!playing) break
            delay(250)
        }
    }
    return position to duration
}

@Composable
private fun PlayerArtwork(entry: com.faxel.app.data.Entry, size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val style = Prefs.playerCover.value
    val animated = Prefs.playerAnimations.value && AudioConnection.isPlaying
    val spin = rememberInfiniteTransition(label = "cover-spin")
    val rotation by spin.animateFloat(
        initialValue = 0f, targetValue = if (animated) 360f else 0f,
        animationSpec = infiniteRepeatable(tween(7000, easing = LinearEasing)), label = "cover-rotation",
    )
    when (style) {
        "vinyl" -> Box(modifier.size(size).clip(CircleShape).background(Color(0xFF17171A)), contentAlignment = Alignment.Center) {
            Box(Modifier.fillMaxSize().padding(size * 0.1f).rotate(if (animated) rotation else 0f)
                .clip(CircleShape).background(Surface2), contentAlignment = Alignment.Center) {
                if (entry.thumbnail != null) AsyncImage(entry.thumbnail, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().padding(size * 0.16f).clip(CircleShape))
                else Thumb(null, entry.path, modifier = Modifier.fillMaxSize().padding(size * 0.16f).clip(CircleShape), shape = CircleShape, audio = true)
                Box(Modifier.size(size * 0.12f).clip(CircleShape).background(Color(0xFF101014)).border(2.dp, Color.White.copy(alpha = 0.45f), CircleShape))
            }
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(Color.White.copy(alpha = 0.12f), style = Stroke(width = 1.dp.toPx()))
                drawCircle(Color.White.copy(alpha = 0.08f), radius = this.size.minDimension * 0.42f, style = Stroke(width = 1.dp.toPx()))
            }
        }
        "cassette" -> Column(modifier.size(size).clip(RoundedCornerShape(20.dp)).background(Color(0xFF28272D))
            .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(20.dp)).padding(size * 0.09f),
            verticalArrangement = Arrangement.SpaceBetween, horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(9.dp)).background(Surface1), contentAlignment = Alignment.Center) {
                if (entry.thumbnail != null) AsyncImage(entry.thumbnail, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                else Icon(Icons.Rounded.MusicNote, null, tint = accent, modifier = Modifier.size(size * 0.25f))
            }
            Row(Modifier.fillMaxWidth().padding(top = size * 0.06f), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                repeat(2) {
                    Box(Modifier.size(size * 0.17f).rotate(if (animated) rotation else 0f).clip(CircleShape)
                        .background(Color(0xFF15151B)).border(3.dp, Color.White.copy(alpha = 0.65f), CircleShape), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(size * 0.045f).clip(CircleShape).background(accent))
                    }
                }
                Canvas(Modifier.width(size * 0.34f).height(size * 0.12f)) {
                    drawRoundRect(Color(0xFF45424B), cornerRadius = androidx.compose.ui.geometry.CornerRadius(this.size.width * 0.04f))
                }
            }
        }
        else -> Thumb(entry.thumbnail, entry.path, size, shape = RoundedCornerShape(18.dp), audio = true, modifier = modifier)
    }
}

@Composable
private fun PlayerVisualizer(modifier: Modifier = Modifier) {
    val style = Prefs.visualizerStyle.value
    if (style == "none") return
    val spectrum = AudioFx.spectrum
    Canvas(modifier) {
        val count = 26
        val gap = 3.dp.toPx()
        val width = (size.width - gap * (count - 1)) / count
        for (i in 0 until count) {
            val value = spectrum.getOrElse(i) { 0f }.coerceIn(0f, 1f)
            val amplitude = (0.12f + value * 0.88f) * size.height
            val height = if (style == "wave") amplitude.coerceAtLeast(size.height * (0.18f + 0.62f * kotlin.math.abs(kotlin.math.sin(i * 0.34f)))) else amplitude
            val top = if (style == "wave") (size.height - height) / 2 else size.height - height
            drawRoundRect(
                color = accent.copy(alpha = 0.65f + value * 0.35f),
                topLeft = Offset(i * (width + gap), top),
                size = Size(width, height.coerceAtLeast(3.dp.toPx())),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(width / 2, width / 2),
            )
        }
    }
}

@Composable
fun AudioScreen(onClose: () -> Unit) {
    val entry = AudioConnection.current ?: return
    val (position, duration) = rememberAudioPosition()
    val context = LocalContext.current
    val visualizerPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        Prefs.visualizerPermissionAsked.value = true
        if (allowed && Prefs.visualizerStyle.value != "none") AudioFx.startVisualizer()
    }
    LaunchedEffect(Prefs.visualizerStyle.value, entry.path) {
        if (Prefs.visualizerStyle.value == "none") {
            AudioFx.stopVisualizer()
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            AudioFx.startVisualizer()
        } else if (!Prefs.visualizerPermissionAsked.value) {
            visualizerPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    DisposableEffect(Unit) { onDispose { AudioFx.stopVisualizer() } }
    val backgroundStyle = Prefs.playerBackground.value
    val backgroundImage = when (backgroundStyle) {
        "photo" -> Prefs.playerBackgroundPhoto.value.takeIf { it.isNotBlank() }
        "artwork" -> entry.thumbnail
        else -> null
    }
    val backgroundBrush = if (backgroundStyle == "black" || backgroundStyle == "photo" || backgroundStyle == "artwork") {
        null
    } else {
        Brush.linearGradient(gradientFor(entry.path))
    }
    Box(
        Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { } },
    ) {
        if (backgroundBrush != null) Box(Modifier.fillMaxSize().background(backgroundBrush))
        if (backgroundImage != null) {
            AsyncImage(backgroundImage, null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(60.dp) else Modifier))
        }
        if (Prefs.dimPlayerBackground.value) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.56f)))
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            val boxW = maxWidth
            val boxH = maxHeight
            val wide = boxW > boxH && boxW >= 560.dp
            if (wide) {
                Row(Modifier.fillMaxSize().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.Center) {
                        Header(onClose)
                        PlayerArtwork(entry, minOf(boxH * 0.5f, 360.dp), Modifier.align(Alignment.CenterHorizontally))
                        PlayerVisualizer(Modifier.fillMaxWidth().height(28.dp).padding(horizontal = 24.dp))
                        Spacer(Modifier.height(12.dp))
                        Controls(position, duration)
                    }
                    QueueList(Modifier.weight(1f).fillMaxHeight())
                }
            } else {
                Column(Modifier.fillMaxSize().padding(horizontal = 22.dp)) {
                    Header(onClose)
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            PlayerArtwork(entry, minOf(boxW - 44.dp, boxH * 0.4f))
                            Spacer(Modifier.height(14.dp))
                            PlayerVisualizer(Modifier.width(minOf(boxW - 72.dp, 320.dp)).height(32.dp))
                        }
                    }
                    Controls(position, duration)
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
    }
}

@Composable
private fun Header(onClose: () -> Unit) {
    var speedMenu by remember { mutableStateOf(false) }
    var sleepMenu by remember { mutableStateOf(false) }
    var eqOpen by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(38.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).clickable(onClick = onClose), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = Color.White)
        }
        Text(
            stringResource(R.string.index_of, AudioConnection.index + 1, AudioConnection.queue.size),
            color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp, modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
        )
        IconButton(onClick = { eqOpen = true }) {
            Icon(Icons.Rounded.Equalizer, null, tint = if (com.faxel.app.playback.AudioFx.enabled) accent else Color.White)
        }
        Box {
            IconButton(onClick = { sleepMenu = true }) {
                Icon(Icons.Rounded.Timer, null, tint = if (AudioConnection.sleepEnd != null) accent else Color.White)
            }
            DropdownMenu(sleepMenu, onDismissRequest = { sleepMenu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.v_sleep_off)) }, onClick = { AudioConnection.setSleepTimer(0); sleepMenu = false })
                listOf(5, 10, 15, 30, 45, 60, 90).forEach { minutes ->
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.v_minutes, minutes)) },
                        onClick = { AudioConnection.setSleepTimer(minutes); sleepMenu = false },
                    )
                }
            }
        }
        Box {
            TextButton(onClick = { speedMenu = true }) { Text("${AudioConnection.speed}×", color = Color.White) }
            DropdownMenu(speedMenu, onDismissRequest = { speedMenu = false }) {
                listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).forEach { value ->
                    DropdownMenuItem(text = { Text("$value×") }, onClick = { AudioConnection.setSpeed(value); speedMenu = false })
                }
            }
        }
        Box(Modifier.size(38.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).clickable { AudioConnection.stop(); onClose() },
            contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Close, null, tint = Color.White)
        }
    }
    if (eqOpen) EqualizerSheet(onDismiss = { eqOpen = false })
}

@Composable
private fun Controls(position: Long, duration: Long) {
    val entry = AudioConnection.current ?: return
    var dragging by remember { mutableStateOf<Float?>(null) }
    val fraction = dragging ?: if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Column {
        Text(entry.title, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(entry.uploader.ifBlank { entry.platformName }, color = Color.White.copy(alpha = 0.65f), fontSize = 15.sp, maxLines = 1)
        Slider(
            value = fraction,
            onValueChange = { dragging = it },
            onValueChangeFinished = { dragging?.let { AudioConnection.seek((it * duration).toLong()) }; dragging = null },
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.2f)),
        )
        Row(Modifier.fillMaxWidth()) {
            val shown = if (dragging != null) (fraction * duration).toLong() else position
            Text(formatMs(shown), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp, modifier = Modifier.weight(1f))
            Text("-" + formatMs((duration - shown).coerceAtLeast(0)), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { AudioConnection.toggleShuffle() }) {
                Icon(Icons.Rounded.Shuffle, null, tint = if (AudioConnection.shuffle) accent else Color.White.copy(alpha = 0.7f))
            }
            IconButton(onClick = { AudioConnection.previous() }, modifier = Modifier.size(56.dp)) {
                Icon(Icons.Rounded.SkipPrevious, null, tint = Color.White, modifier = Modifier.size(42.dp))
            }
            Box(Modifier.size(72.dp).clip(CircleShape).background(Color.White).clickable { AudioConnection.toggle() }, contentAlignment = Alignment.Center) {
                Icon(if (AudioConnection.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(42.dp))
            }
            IconButton(onClick = { AudioConnection.next() }, modifier = Modifier.size(56.dp)) {
                Icon(Icons.Rounded.SkipNext, null, tint = Color.White, modifier = Modifier.size(42.dp))
            }
            IconButton(onClick = { AudioConnection.cycleRepeat() }) {
                Icon(
                    if (AudioConnection.repeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat, null,
                    tint = if (AudioConnection.repeatMode != Player.REPEAT_MODE_OFF) accent else Color.White.copy(alpha = 0.7f),
                )
            }
        }
    }
}

@Composable
private fun QueueList(modifier: Modifier) {
    val paths = AudioConnection.queue
    Column(modifier) {
        Text(stringResource(R.string.queue), color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 8.dp))
        LazyColumn {
            itemsIndexed(paths, key = { i, p -> "$i-$p" }) { index, path ->
                val entry = com.faxel.app.engine.Engine.entry(path)
                val current = index == AudioConnection.index
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { AudioConnection.jump(index) }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Thumb(entry?.thumbnail, path, 40.dp, audio = true)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        entry?.title ?: java.io.File(path).nameWithoutExtension,
                        color = if (current) accent else Color.White, fontWeight = if (current) FontWeight.Bold else FontWeight.Normal,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    if (!current) IconButton(onClick = { AudioConnection.removeAt(index) }) { Icon(Icons.Rounded.Close, null, tint = Muted) }
                }
            }
        }
    }
}

// MARK: Égaliseur

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EqualizerSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.equalizer), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Switch(AudioFx.enabled, { AudioFx.setEnabled(it) })
            }
            if (AudioFx.bandCount == 0) {
                Text(stringResource(R.string.eq_unavailable), color = Color.Gray, modifier = Modifier.padding(vertical = 12.dp))
                return@Column
            }
            if (AudioFx.presets.isNotEmpty()) {
                androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 10.dp)) {
                    items(AudioFx.presets.size) { index ->
                        val selected = AudioFx.preset == index
                        Text(
                            AudioFx.presets[index],
                            color = if (selected) Color.White else Color.White.copy(alpha = 0.8f),
                            fontSize = 14.sp,
                            modifier = Modifier
                                .clip(RoundedCornerShape(20.dp))
                                .background(if (selected) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.1f))
                                .clickable { AudioFx.usePreset(index) }
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            AudioFx.levels.forEachIndexed { band, level ->
                val freq = AudioFx.bandFrequencies.getOrNull(band) ?: 0
                val label = if (freq >= 1000) "${freq / 1000} kHz" else "$freq Hz"
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.width(64.dp))
                    Slider(
                        value = level.toFloat(),
                        onValueChange = { AudioFx.setLevel(band, it.toInt()) },
                        valueRange = AudioFx.range.first.toFloat()..AudioFx.range.last.toFloat(),
                        modifier = Modifier.weight(1f),
                    )
                    Text("%+.0f dB".format(level / 100f), color = Color.White, fontSize = 12.sp, modifier = Modifier.width(52.dp), textAlign = TextAlign.End)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.bass), color = Color.Gray, fontSize = 12.sp, modifier = Modifier.width(64.dp))
                Slider(AudioFx.bass.toFloat(), { AudioFx.setBass(it.toInt()) }, valueRange = 0f..1000f, modifier = Modifier.weight(1f))
                Text("${AudioFx.bass / 10}%", color = Color.White, fontSize = 12.sp, modifier = Modifier.width(52.dp), textAlign = TextAlign.End)
            }
            TextButton(onClick = { AudioFx.reset() }) { Text(stringResource(R.string.reset)) }
        }
    }
}
