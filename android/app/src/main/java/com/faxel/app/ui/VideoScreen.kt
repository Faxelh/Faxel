package com.faxel.app.ui

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.media.AudioManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import android.view.SurfaceView
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.BrightnessMedium
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.ScreenRotation
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.VolumeOff
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
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
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.faxel.app.MainActivity
import com.faxel.app.R
import com.faxel.app.playback.VideoState
import kotlinx.coroutines.delay
import java.io.File
import kotlin.math.abs

private val SPEEDS = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f)

/**
 * Lecteur vidéo plein écran : gestes (double-toucher ±10 s, appui long ×2, glisser à gauche
 * pour la luminosité, à droite pour le volume, à l'horizontale pour avancer), sous-titres,
 * pistes audio, vitesse, répétition, minuterie, épisode suivant, verrou, capture, filigrane.
 */
@OptIn(UnstableApi::class)
@Composable
fun VideoScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val activity = context as? Activity
    val view = LocalView.current
    val pip = VideoState.inPip
    val player = VideoState.player

    var controls by remember { mutableStateOf(true) }
    var locked by remember { mutableStateOf(false) }
    var touchTick by remember { mutableIntStateOf(0) }
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    var buffering by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf<Float?>(null) }
    var gestureSeek by remember { mutableStateOf<Long?>(null) }
    var gestureStart by remember { mutableLongStateOf(0L) }
    var hudLeft by remember { mutableStateOf<Float?>(null) }
    var hudRight by remember { mutableStateOf<Float?>(null) }
    var flash by remember { mutableStateOf<Pair<Boolean, Int>?>(null) }
    var flashTick by remember { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf<String?>(null) }
    var rotationLocked by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var watermarkFile by remember { mutableStateOf<File?>(null) }
    var surface by remember { mutableStateOf<SurfaceView?>(null) }

    val audio = remember { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }

    BackHandler(enabled = !pip) {
        when {
            menu != null -> menu = null
            locked -> controls = true
            else -> onClose()
        }
    }

    // Plein écran : barres du système cachées ; tout est rendu à la fermeture.
    DisposableEffect(Unit) {
        val window = activity?.window
        val insets = window?.let { WindowCompat.getInsetsController(it, view) }
        insets?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets?.hide(WindowInsetsCompat.Type.systemBars())
        view.keepScreenOn = true
        onDispose {
            insets?.show(WindowInsetsCompat.Type.systemBars())
            view.keepScreenOn = false
            VideoState.setBoost(false)
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            window?.let { w -> w.attributes = w.attributes.apply { screenBrightness = -1f } }
        }
    }

    // Position (barre de progression, épisode suivant).
    LaunchedEffect(player) {
        while (true) {
            val exo = VideoState.player ?: break
            position = exo.currentPosition.coerceAtLeast(0)
            duration = exo.duration.takeIf { it > 0 } ?: 0L
            buffering = exo.playbackState == Player.STATE_BUFFERING
            delay(250)
        }
    }

    // Les commandes se cachent seules pendant la lecture.
    LaunchedEffect(controls, VideoState.isPlaying, touchTick, menu, dragging) {
        if (controls && VideoState.isPlaying && menu == null && dragging == null) {
            delay(3500)
            controls = false
        }
    }

    LaunchedEffect(flashTick) {
        if (flash != null) {
            delay(800)
            flash = null
        }
    }

    val sleepStopped = stringResource(R.string.v_sleep_stopped)
    LaunchedEffect(VideoState.notice) {
        if (VideoState.notice == "sleep") {
            notice = sleepStopped
            VideoState.notice = null
        }
    }
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(1800)
            notice = null
        }
    }

    fun show() {
        controls = true
        touchTick++
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    setKeepContentOnPlayerReset(true)
                    surface = videoSurfaceView as? SurfaceView
                }
            },
            update = { playerView ->
                if (playerView.player !== VideoState.player) playerView.player = VideoState.player
                playerView.resizeMode = when (VideoState.resize) {
                    1 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    2 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                    else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
            },
            modifier = Modifier.fillMaxSize(),
        )

        if (!pip) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val widthPx = constraints.maxWidth.toFloat()
                val heightPx = constraints.maxHeight.toFloat()
                Box(
                    Modifier
                        .fillMaxSize()
                        .pointerInput(locked) {
                            detectTapGestures(
                                onTap = {
                                    if (controls && !locked) controls = false else show()
                                },
                                onDoubleTap = { offset ->
                                    if (locked) return@detectTapGestures
                                    val forward = offset.x > widthPx / 2
                                    VideoState.seekBy(if (forward) 10_000 else -10_000)
                                    val amount = (flash?.takeIf { it.first == forward }?.second ?: 0) + 10
                                    flash = forward to amount
                                    flashTick++
                                },
                                onLongPress = {
                                    if (!locked && VideoState.isPlaying) VideoState.setBoost(true)
                                },
                                onPress = {
                                    tryAwaitRelease()
                                    VideoState.setBoost(false)
                                },
                            )
                        }
                        .pointerInput(locked) {
                            if (locked) return@pointerInput
                            var kind = 0
                            var startX = 0f
                            var total = Offset.Zero
                            var startLevel = 0f
                            detectDragGestures(
                                onDragStart = { offset ->
                                    kind = 0
                                    startX = offset.x
                                    total = Offset.Zero
                                },
                                onDragEnd = {
                                    gestureSeek?.let { VideoState.seekTo(it) }
                                    gestureSeek = null
                                    hudLeft = null
                                    hudRight = null
                                    kind = 0
                                },
                                onDragCancel = {
                                    gestureSeek = null
                                    hudLeft = null
                                    hudRight = null
                                    kind = 0
                                },
                            ) { change, amount ->
                                change.consume()
                                total += amount
                                if (kind == 0) {
                                    if (abs(total.x) < 18 && abs(total.y) < 18) return@detectDragGestures
                                    if (abs(total.y) > abs(total.x)) {
                                        kind = if (startX < widthPx / 2) 1 else 2
                                        startLevel = if (kind == 1) currentBrightness(activity) else {
                                            audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
                                                audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                                        }
                                    } else {
                                        kind = 3
                                        gestureStart = VideoState.player?.currentPosition ?: 0L
                                        show()
                                    }
                                }
                                when (kind) {
                                    1, 2 -> {
                                        val level = (startLevel - total.y / (heightPx * 0.6f)).coerceIn(0f, 1f)
                                        if (kind == 1) {
                                            activity?.window?.let { window ->
                                                window.attributes = window.attributes.apply { screenBrightness = level.coerceAtLeast(0.01f) }
                                            }
                                            hudLeft = level
                                        } else {
                                            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, (level * max).toInt(), 0)
                                            hudRight = level
                                        }
                                    }
                                    3 -> {
                                        val span = minOf(maxOf(duration, 1L), 180_000L)
                                        val target = gestureStart + (total.x / widthPx * span).toLong()
                                        gestureSeek = target.coerceIn(0L, maxOf(duration, 0L))
                                    }
                                }
                            }
                        },
                )
            }
        }

        if (buffering && dragging == null) {
            CircularProgressIndicator(Modifier.align(Alignment.Center).size(48.dp), color = Color.White)
        }

        // Bulles ±10 s
        flash?.let { (forward, amount) ->
            Box(
                Modifier.align(if (forward) Alignment.CenterEnd else Alignment.CenterStart)
                    .padding(horizontal = 48.dp).size(110.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(if (forward) Icons.Rounded.Forward10 else Icons.Rounded.Replay10, null, tint = Color.White, modifier = Modifier.size(34.dp))
                    Text((if (forward) "+" else "−") + "$amount s", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }

        // Luminosité (gauche) et volume (droite)
        hudLeft?.let { VerticalHud(it, Icons.Rounded.BrightnessMedium, Modifier.align(Alignment.CenterStart).padding(start = 36.dp)) }
        hudRight?.let {
            VerticalHud(it, if (it == 0f) Icons.Rounded.VolumeOff else Icons.Rounded.VolumeUp,
                Modifier.align(Alignment.CenterEnd).padding(end = 36.dp))
        }

        // Avance / recul en glissant
        gestureSeek?.let { target ->
            val delta = target - gestureStart
            Column(
                Modifier.align(Alignment.Center).clip(RoundedCornerShape(18.dp)).background(Color.Black.copy(alpha = 0.65f))
                    .padding(horizontal = 22.dp, vertical = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(formatMs(target), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Text((if (delta >= 0) "+" else "−") + formatMs(abs(delta)), color = Color.White.copy(alpha = 0.75f), fontSize = 15.sp)
            }
        }

        if (VideoState.boosted) {
            Row(
                Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 24.dp)
                    .clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.65f)).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.FastForward, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.v_speed2), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
        }

        // Épisode suivant : 5, 4, 3, 2, 1 en vraies secondes (VideoState mène le compte).
        val remaining = ((duration - position) / VideoState.speed.coerceAtLeast(0.25f)).toLong()
        val canNext = VideoState.hasNext && !VideoState.repeatOne && !VideoState.cancelAutoNext &&
            !VideoState.sleepAtEnd && duration > 30_000
        LaunchedEffect(canNext, remaining / 500, VideoState.isPlaying) {
            when {
                !canNext -> VideoState.stopCountdown()
                VideoState.nextCountdown == null && VideoState.isPlaying && remaining in 1..5_000 ->
                    VideoState.startCountdown(((remaining + 999) / 1000).toInt())
                VideoState.nextCountdown != null && remaining > 5_500 -> VideoState.stopCountdown()
            }
        }
        val countdown = VideoState.nextCountdown
        if (!pip && !locked && canNext && countdown != null) {
            NextCard(
                seconds = countdown,
                title = VideoState.files.getOrNull(VideoState.index + 1)?.nameWithoutExtension ?: "",
                modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(end = 24.dp, bottom = 110.dp),
            )
        }

        notice?.let {
            Text(
                it, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 70.dp)
                    .clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }

        // Écran verrouillé : seul le cadenas apparaît.
        if (locked && controls && !pip) {
            IconButton(
                onClick = { locked = false; show() },
                modifier = Modifier.align(Alignment.CenterStart).padding(start = 24.dp).size(56.dp)
                    .clip(CircleShape).background(Color.Black.copy(alpha = 0.6f)),
            ) { Icon(Icons.Rounded.Lock, null, tint = Color.White) }
        }

        AnimatedVisibility(visible = controls && !locked && !pip, enter = fadeIn(), exit = fadeOut()) {
            val lockedText = stringResource(R.string.v_locked)
            val shotText = stringResource(R.string.v_shot_saved)
            Box(Modifier.fillMaxSize()) {
                // Haut : retour, titre, sous-titres, pistes audio, plus
                Row(
                    Modifier.fillMaxWidth().align(Alignment.TopCenter)
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.75f), Color.Transparent)))
                        .statusBarsPadding().padding(horizontal = 4.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = Color.White) }
                    Column(Modifier.weight(1f)) {
                        Text(VideoState.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (VideoState.files.size > 1) {
                            Text(stringResource(R.string.index_of, VideoState.index + 1, VideoState.files.size),
                                color = Color.White.copy(alpha = 0.65f), fontSize = 12.sp)
                        }
                    }
                    Box {
                        IconButton(onClick = { menu = "subs"; show() }) { Icon(Icons.Rounded.ClosedCaption, null, tint = Color.White) }
                        TrackMenu(menu == "subs", C.TRACK_TYPE_TEXT, allowOff = true) { menu = null }
                    }
                    Box {
                        IconButton(onClick = { menu = "audio"; show() }) { Icon(Icons.Rounded.Audiotrack, null, tint = Color.White) }
                        TrackMenu(menu == "audio", C.TRACK_TYPE_AUDIO, allowOff = false) { menu = null }
                    }
                    Box {
                        IconButton(onClick = { menu = "more"; show() }) { Icon(Icons.Rounded.MoreVert, null, tint = Color.White) }
                        MoreMenu(
                            open = menu == "more" || menu == "speed" || menu == "sleep",
                            page = menu ?: "more",
                            onPage = { menu = it },
                            onClose = { menu = null },
                            onShot = {
                                capture(context, surface) { ok -> if (ok) notice = shotText }
                            },
                            onWatermark = {
                                VideoState.pause()
                                watermarkFile = VideoState.current
                            },
                        )
                    }
                }

                // Centre : précédent, -10 s, lecture, +10 s, suivant
                Row(
                    Modifier.align(Alignment.Center),
                    horizontalArrangement = Arrangement.spacedBy(22.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (VideoState.files.size > 1) RoundButton(Icons.Rounded.SkipPrevious, 48) { VideoState.previous(); show() }
                    RoundButton(Icons.Rounded.Replay10, 52) { VideoState.seekBy(-10_000); show() }
                    Box(
                        Modifier.size(76.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f))
                            .clickable { VideoState.toggle(); show() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(if (VideoState.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null,
                            tint = Color.White, modifier = Modifier.size(46.dp))
                    }
                    RoundButton(Icons.Rounded.Forward10, 52) { VideoState.seekBy(10_000); show() }
                    if (VideoState.files.size > 1) RoundButton(Icons.Rounded.SkipNext, 48) { VideoState.next(); show() }
                }

                // Bas : barre de progression et outils
                Column(
                    Modifier.fillMaxWidth().align(Alignment.BottomCenter)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))))
                        .navigationBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp),
                ) {
                    val shown = dragging?.let { (it * duration).toLong() } ?: position
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(formatMs(shown), color = Color.White, fontSize = 12.sp)
                        Slider(
                            value = dragging ?: if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f,
                            onValueChange = { dragging = it; show() },
                            onValueChangeFinished = {
                                dragging?.let { VideoState.seekTo((it * duration).toLong()) }
                                dragging = null
                            },
                            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = accent,
                                inactiveTrackColor = Color.White.copy(alpha = 0.25f)),
                            modifier = Modifier.weight(1f).padding(horizontal = 10.dp),
                        )
                        Text("-" + formatMs((duration - shown).coerceAtLeast(0)), color = Color.White, fontSize = 12.sp)
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                        ToolButton(Icons.Rounded.AspectRatio, stringResource(
                            when (VideoState.resize) { 1 -> R.string.v_fill; 2 -> R.string.v_stretch; else -> R.string.v_fit },
                        )) { VideoState.resize = (VideoState.resize + 1) % 3; show() }
                        ToolButton(Icons.Rounded.ScreenRotation, stringResource(if (rotationLocked) R.string.v_rotation_locked else R.string.v_rotate)) {
                            val landscape = context.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                            activity?.requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                            else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                            rotationLocked = true
                            show()
                        }
                        ToolButton(Icons.Rounded.Lock, stringResource(R.string.v_lock)) {
                            locked = true
                            notice = lockedText
                        }
                        ToolButton(null, "${formatSpeed(if (VideoState.boosted) 2f else VideoState.speed)}×") {
                            menu = "speed"
                        }
                        if (Build.VERSION.SDK_INT >= 26) {
                            ToolButton(Icons.Rounded.PictureInPictureAlt, stringResource(R.string.v_pip)) {
                                (activity as? MainActivity)?.enterPip()
                            }
                        }
                    }
                }
            }
        }
    }

    watermarkFile?.let { file ->
        WatermarkScreen(file, onClose = { watermarkFile = null })
    }
}

private fun formatSpeed(value: Float): String =
    if (value % 1f == 0f) value.toInt().toString() else value.toString().trimEnd('0')

private fun currentBrightness(activity: Activity?): Float {
    val value = activity?.window?.attributes?.screenBrightness ?: -1f
    if (value >= 0f) return value
    return runCatching {
        android.provider.Settings.System.getInt(activity?.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS) / 255f
    }.getOrDefault(0.5f)
}

/** Capture de l'image affichée, enregistrée dans Images › Faxel. */
private fun capture(context: Context, surface: SurfaceView?, done: (Boolean) -> Unit) {
    val view = surface ?: return done(false)
    if (Build.VERSION.SDK_INT < 24 || view.width <= 0 || view.height <= 0) return done(false)
    val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
    PixelCopy.request(view, bitmap, { result ->
        if (result != PixelCopy.SUCCESS) {
            done(false)
            return@request
        }
        val ok = runCatching {
            val name = "Faxel_${System.currentTimeMillis()}.jpg"
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Faxel")
                }
                val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("uri")
                context.contentResolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
            } else {
                val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Faxel").apply { mkdirs() }
                val file = File(folder, name)
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                android.media.MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null, null)
            }
            true
        }.getOrDefault(false)
        done(ok)
    }, Handler(Looper.getMainLooper()))
}

@Composable
private fun VerticalHud(value: Float, icon: ImageVector, modifier: Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(26.dp)).background(Color.Black.copy(alpha = 0.6f)).padding(vertical = 14.dp).width(52.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("${(value * 100).toInt()}", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Box(Modifier.width(8.dp).height(150.dp).clip(RoundedCornerShape(4.dp)).background(Color.White.copy(alpha = 0.25f)),
            contentAlignment = Alignment.BottomCenter) {
            Box(Modifier.width(8.dp).height((150 * value).coerceAtLeast(6f).dp).clip(RoundedCornerShape(4.dp)).background(Color.White))
        }
        Spacer(Modifier.height(8.dp))
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun RoundButton(icon: ImageVector, size: Int, onClick: () -> Unit) {
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.25f)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size((size * 0.6f).dp)) }
}

@Composable
private fun ToolButton(icon: ImageVector?, label: String, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
        } else {
            Text(label, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.height(22.dp))
        }
        if (icon != null) Text(label, color = Color.White.copy(alpha = 0.8f), fontSize = 11.sp, maxLines = 1)
    }
}

@Composable
private fun NextCard(seconds: Int, title: String, modifier: Modifier) {
    Column(
        modifier.widthIn(max = 300.dp).clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha = 0.78f)).padding(14.dp),
    ) {
        Text(stringResource(R.string.v_next_in, seconds), color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp)
        if (title.isNotBlank()) {
            Text(title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.v_play), color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White).clickable { VideoState.next() }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
            Text(
                stringResource(R.string.cancel), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.18f)).clickable { VideoState.cancelNext() }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun TrackMenu(open: Boolean, type: Int, allowOff: Boolean, onClose: () -> Unit) {
    // Relu quand les pistes changent.
    val version = VideoState.tracksVersion
    val choices = remember(version, open) { VideoState.choices(type) }
    DropdownMenu(expanded = open, onDismissRequest = onClose) {
        if (allowOff) {
            val anySelected = choices.any { it.selected }
            DropdownMenuItem(
                text = { Text((if (!anySelected) "✓ " else "") + stringResource(R.string.v_subs_off)) },
                onClick = { VideoState.select(type, null); onClose() },
            )
        }
        if (choices.isEmpty()) {
            DropdownMenuItem(text = { Text(stringResource(R.string.v_none)) }, onClick = onClose, enabled = false)
        }
        choices.forEach { choice ->
            DropdownMenuItem(
                text = { Text((if (choice.selected) "✓ " else "") + choice.label) },
                onClick = { VideoState.select(type, choice); onClose() },
            )
        }
    }
}

@Composable
private fun MoreMenu(
    open: Boolean,
    page: String,
    onPage: (String) -> Unit,
    onClose: () -> Unit,
    onShot: () -> Unit,
    onWatermark: () -> Unit,
) {
    DropdownMenu(expanded = open, onDismissRequest = onClose) {
        when (page) {
            "speed" -> SPEEDS.forEach { value ->
                DropdownMenuItem(
                    text = { Text((if (VideoState.speed == value) "✓ " else "") + formatSpeed(value) + "×") },
                    onClick = { VideoState.setSpeed(value); onClose() },
                )
            }
            "sleep" -> {
                DropdownMenuItem(text = { Text(stringResource(R.string.v_sleep_off)) }, onClick = { VideoState.setSleep(0); onClose() })
                DropdownMenuItem(text = { Text(stringResource(R.string.v_sleep_end)) }, onClick = { VideoState.setSleep(-1); onClose() })
                listOf(15, 30, 45, 60, 90).forEach { minutes ->
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.v_minutes, minutes)) },
                        onClick = { VideoState.setSleep(minutes); onClose() },
                    )
                }
            }
            else -> {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.v_speed) + " : " + formatSpeed(VideoState.speed) + "×") },
                    onClick = { onPage("speed") },
                )
                DropdownMenuItem(
                    text = { Text((if (VideoState.repeatOne) "✓ " else "") + stringResource(R.string.v_repeat)) },
                    onClick = { VideoState.toggleRepeat(); onClose() },
                )
                val sleepText = when {
                    VideoState.sleepAtEnd -> stringResource(R.string.v_sleep_end)
                    VideoState.sleepEnd != null -> stringResource(R.string.v_minutes,
                        (((VideoState.sleepEnd ?: 0L) - System.currentTimeMillis()) / 60_000L + 1).toInt())
                    else -> stringResource(R.string.v_sleep_off)
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.v_sleep) + " : " + sleepText) },
                    onClick = { onPage("sleep") },
                )
                HorizontalDivider()
                DropdownMenuItem(text = { Text(stringResource(R.string.v_screenshot)) }, onClick = { onClose(); onShot() })
                DropdownMenuItem(text = { Text(stringResource(R.string.wm_title) + "…") }, onClick = { onClose(); onWatermark() })
            }
        }
    }
}
