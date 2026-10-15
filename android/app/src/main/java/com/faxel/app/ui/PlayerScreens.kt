package com.faxel.app.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.view.View
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
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
fun AudioScreen(onClose: () -> Unit) {
    val entry = AudioConnection.current ?: return
    val (position, duration) = rememberAudioPosition()
    Box(
        Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { } },
    ) {
        // Fond : la miniature floutée (Android 12+) sur un dégradé.
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(gradientFor(entry.path)[0].copy(alpha = 0.6f), Color.Black))))
        if (Build.VERSION.SDK_INT >= 31 && entry.thumbnail != null) {
            AsyncImage(entry.thumbnail, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().blur(60.dp))
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)))
        }
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            val boxW = maxWidth
            val boxH = maxHeight
            val wide = boxW > boxH && boxW >= 560.dp
            if (wide) {
                Row(Modifier.fillMaxSize().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.Center) {
                        Header(onClose)
                        Thumb(entry.thumbnail, entry.path, minOf(boxH * 0.5f, 360.dp), shape = RoundedCornerShape(18.dp), audio = true,
                            modifier = Modifier.align(Alignment.CenterHorizontally))
                        Spacer(Modifier.height(12.dp))
                        Controls(position, duration)
                    }
                    QueueList(Modifier.weight(1f).fillMaxHeight())
                }
            } else {
                Column(Modifier.fillMaxSize().padding(horizontal = 22.dp)) {
                    Header(onClose)
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Thumb(entry.thumbnail, entry.path, minOf(boxW - 44.dp, boxH * 0.45f), shape = RoundedCornerShape(18.dp), audio = true)
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
