package com.faxel.app.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.opengl.GLES20
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.faxel.app.R
import com.faxel.app.engine.Engine
import com.faxel.app.engine.Storage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File

// MARK: Effet GPU : flou ou pixels dans des zones

private const val MAX_ZONES = 6

private const val VERTEX_SHADER = """
attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;
void main() {
  gl_Position = aFramePosition;
  vTexSamplingCoord = vec2(aFramePosition.x * 0.5 + 0.5, aFramePosition.y * 0.5 + 0.5);
}
"""

private const val FRAGMENT_SHADER = """
precision highp float;
uniform sampler2D uTexSampler;
uniform vec2 uTexel;
uniform float uRadius;
uniform float uMode;
uniform float uCount;
uniform vec4 uZone0;
uniform vec4 uZone1;
uniform vec4 uZone2;
uniform vec4 uZone3;
uniform vec4 uZone4;
uniform vec4 uZone5;
varying vec2 vTexSamplingCoord;

bool inZone(vec4 z, vec2 p) {
  return p.x >= z.x && p.x <= z.z && p.y >= z.y && p.y <= z.w;
}

vec4 blurAt(vec2 p) {
  vec4 sum = vec4(0.0);
  for (int i = -4; i <= 4; i++) {
    for (int j = -4; j <= 4; j++) {
      vec2 o = vec2(float(i), float(j)) * uTexel * uRadius * 0.5;
      sum += texture2D(uTexSampler, p + o);
    }
  }
  return sum / 81.0;
}

vec4 pixelAt(vec2 p) {
  vec2 cell = uTexel * uRadius * 1.5;
  vec2 q = (floor(p / cell) + 0.5) * cell;
  return texture2D(uTexSampler, q);
}

void main() {
  vec2 p = vTexSamplingCoord;
  vec4 color = texture2D(uTexSampler, p);
  bool hit = (uCount > 0.5 && inZone(uZone0, p))
    || (uCount > 1.5 && inZone(uZone1, p))
    || (uCount > 2.5 && inZone(uZone2, p))
    || (uCount > 3.5 && inZone(uZone3, p))
    || (uCount > 4.5 && inZone(uZone4, p))
    || (uCount > 5.5 && inZone(uZone5, p));
  if (hit) {
    color = uMode > 0.5 ? pixelAt(p) : blurAt(p);
  }
  gl_FragColor = color;
}
"""

/** Zones en proportions de l'image (0…1, origine en haut à gauche). */
@UnstableApi
class ZoneBlurEffect(private val zones: List<RectF>, private val pixelate: Boolean, private val strength: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        ZoneBlurProgram(zones, pixelate, strength, useHdr)
}

@UnstableApi
private class ZoneBlurProgram(
    zones: List<RectF>,
    private val pixelate: Boolean,
    private val strength: Float,
    useHdr: Boolean,
) : BaseGlShaderProgram(useHdr, 1) {
    private val program = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    // Texture : origine en bas à gauche → on retourne l'axe vertical.
    private val textureZones = zones.take(MAX_ZONES).map { floatArrayOf(it.left, 1f - it.bottom, it.right, 1f - it.top) }
    private var width = 1
    private var height = 1

    init {
        program.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        program.use()
        program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
        program.setFloatsUniform("uTexel", floatArrayOf(1f / width, 1f / height))
        val scale = maxOf(width, height) / 720f
        program.setFloatUniform("uRadius", (4f + strength * 16f) * scale)
        program.setFloatUniform("uMode", if (pixelate) 1f else 0f)
        program.setFloatUniform("uCount", textureZones.size.toFloat())
        for (i in 0 until MAX_ZONES) {
            program.setFloatsUniform("uZone$i", textureZones.getOrNull(i) ?: floatArrayOf(-1f, -1f, -1f, -1f))
        }
        program.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun release() {
        super.release()
        program.delete()
    }
}

// MARK: Export

/** « Ma vidéo (sans filigrane).mp4 » à côté de l'original. */
private fun targetFile(source: File, suffix: String): File {
    val folder = source.parentFile ?: source.absoluteFile.parentFile
    val base = source.nameWithoutExtension + " ($suffix)"
    var candidate = File(folder, "$base.mp4")
    var n = 2
    while (candidate.exists()) {
        candidate = File(folder, "$base $n.mp4")
        n++
    }
    return candidate
}

// MARK: Écran

private data class Zone(val rect: RectF, val id: Long = System.nanoTime())

@OptIn(UnstableApi::class)
@Composable
fun WatermarkScreen(file: File, onClose: () -> Unit) {
    val context = LocalContext.current
    val density = LocalDensity.current
    var frame by remember { mutableStateOf<Bitmap?>(null) }
    var duration by remember { mutableStateOf(0L) }
    var time by remember { mutableFloatStateOf(0f) }
    var zones by remember { mutableStateOf<List<Zone>>(emptyList()) }
    var drawing by remember { mutableStateOf<RectF?>(null) }
    var pixelate by remember { mutableStateOf(false) }
    var strength by remember { mutableFloatStateOf(0.5f) }
    var transformer by remember { mutableStateOf<Transformer?>(null) }
    var progress by remember { mutableFloatStateOf(0f) }
    var result by remember { mutableStateOf<File?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    val suffix = stringResource(R.string.wm_suffix)

    BackHandler {
        transformer?.cancel()
        onClose()
    }

    LaunchedEffect(file) {
        duration = withContext(Dispatchers.IO) {
            runCatching {
                MediaMetadataRetriever().run {
                    setDataSource(file.absolutePath)
                    val d = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    release()
                    d
                }
            }.getOrDefault(0L)
        }
        time = minOf(1000f, duration.toFloat())
    }

    // Image de la vidéo au moment choisi (pour voir où est le logo).
    LaunchedEffect(file, time) {
        delay(150)
        val bitmap = withContext(Dispatchers.IO) {
            runCatching {
                MediaMetadataRetriever().run {
                    setDataSource(file.absolutePath)
                    val b = getFrameAtTime(time.toLong() * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    release()
                    b
                }
            }.getOrNull()
        }
        if (bitmap != null) frame = bitmap
    }

    // Progression de l'export.
    LaunchedEffect(transformer) {
        val running = transformer ?: return@LaunchedEffect
        val holder = ProgressHolder()
        while (transformer === running) {
            if (running.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) progress = holder.progress / 100f
            delay(300)
        }
    }

    DisposableEffect(Unit) {
        onDispose { transformer?.cancel() }
    }

    fun export() {
        val target = targetFile(file, suffix)
        failed = null
        result = null
        progress = 0f
        val effect = ZoneBlurEffect(zones.map { it.rect }, pixelate, strength)
        val edited = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(file)))
            .setEffects(Effects(listOf(), listOf(effect)))
            .build()
        val created = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    transformer = null
                    result = target
                    if (Storage.isPublic) Storage.scan(context, target.absolutePath)
                    Engine.rescan()
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    transformer = null
                    target.delete()
                    failed = exportException.message ?: exportException.errorCodeName
                }
            })
            .build()
        transformer = created
        runCatching { created.start(edited, target.absolutePath) }.onFailure {
            transformer = null
            failed = it.message ?: "?"
        }
    }

    Box(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).blockTouches()) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { transformer?.cancel(); onClose() }) { Icon(Icons.Rounded.Close, null, tint = Color.White) }
                Text(stringResource(R.string.wm_title), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            }
            Column(Modifier.widthIn(max = 760.dp).fillMaxWidth().padding(horizontal = 16.dp)) {
                Text(stringResource(R.string.wm_hint), color = Muted, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))

                val bitmap = frame
                val ratio = bitmap?.let { it.width.toFloat() / it.height.coerceAtLeast(1) } ?: (16f / 9f)
                BoxWithConstraints(
                    Modifier.fillMaxWidth().aspectRatio(ratio.coerceIn(0.4f, 3f)).clip(RoundedCornerShape(12.dp)).background(Color.Black),
                ) {
                    val w = constraints.maxWidth.toFloat()
                    val h = constraints.maxHeight.toFloat()
                    if (bitmap != null) {
                        Image(bitmap.asImageBitmap(), null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
                    } else {
                        CircularProgressIndicator(Modifier.align(Alignment.Center))
                    }
                    Box(
                        Modifier.fillMaxSize().pointerInput(w, h) {
                            var start = Offset.Zero
                            var end = Offset.Zero
                            detectDragGestures(
                                onDragStart = { start = it; end = it },
                                onDragEnd = {
                                    val rect = normalize(start, end, w, h)
                                    drawing = null
                                    if (rect.width() > 0.02f && rect.height() > 0.02f && zones.size < MAX_ZONES) zones = zones + Zone(rect)
                                },
                                onDragCancel = { drawing = null },
                            ) { change, amount ->
                                change.consume()
                                end += amount
                                drawing = normalize(start, end, w, h)
                            }
                        },
                    )
                    zones.forEach { zone ->
                        ZoneBox(zone.rect, w, h, density.density, accent) { zones = zones.filter { it.id != zone.id } }
                    }
                    drawing?.let { ZoneBox(it, w, h, density.density, Color.Yellow, null) }
                }

                if (duration > 1000) {
                    Slider(time, { time = it }, valueRange = 0f..duration.toFloat())
                    Text(stringResource(R.string.wm_frame_at, formatMs(time.toLong())), color = Muted, fontSize = 12.sp)
                }
                Spacer(Modifier.height(10.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip(stringResource(R.string.wm_tiktok), false) {
                        zones = zones + Zone(RectF(0.03f, 0.04f, 0.45f, 0.15f)) + Zone(RectF(0.55f, 0.83f, 0.97f, 0.94f))
                    }
                    Chip(stringResource(R.string.wm_top_left), false) { zones = zones + Zone(RectF(0.02f, 0.03f, 0.32f, 0.15f)) }
                    Chip(stringResource(R.string.wm_top_right), false) { zones = zones + Zone(RectF(0.68f, 0.03f, 0.98f, 0.15f)) }
                    Chip(stringResource(R.string.wm_bottom_left), false) { zones = zones + Zone(RectF(0.02f, 0.85f, 0.32f, 0.97f)) }
                    Chip(stringResource(R.string.wm_bottom_right), false) { zones = zones + Zone(RectF(0.68f, 0.85f, 0.98f, 0.97f)) }
                    if (zones.isNotEmpty()) Chip(stringResource(R.string.wm_clear), false) { zones = emptyList() }
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip(stringResource(R.string.wm_blur), !pixelate) { pixelate = false }
                    Chip(stringResource(R.string.wm_pixels), pixelate) { pixelate = true }
                }
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.wm_strength), color = Color.White, fontWeight = FontWeight.SemiBold)
                Slider(strength, { strength = it })

                Spacer(Modifier.height(8.dp))
                when {
                    transformer != null -> {
                        Text(stringResource(R.string.wm_working, (progress * 100).toInt()), color = Color.White)
                        Spacer(Modifier.height(6.dp))
                        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                        TextButton(onClick = { transformer?.cancel(); transformer = null }) { Text(stringResource(R.string.cancel)) }
                    }
                    result != null -> {
                        Text(stringResource(R.string.wm_done, result!!.name), color = Color(0xFF34C759), fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = onClose, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.ok)) }
                    }
                    else -> {
                        failed?.let { Text(it, color = Color(0xFFFF9F0A), fontSize = 13.sp) }
                        Button(
                            onClick = { export() },
                            enabled = zones.isNotEmpty(),
                            modifier = Modifier.fillMaxWidth().height(50.dp),
                            shape = RoundedCornerShape(14.dp),
                        ) {
                            Icon(Icons.Rounded.AutoFixHigh, null)
                            Spacer(Modifier.size(6.dp))
                            Text(stringResource(R.string.wm_create), fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(stringResource(R.string.wm_keep), color = Muted, fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

private fun normalize(a: Offset, b: Offset, w: Float, h: Float): RectF {
    val x0 = (minOf(a.x, b.x) / w).coerceIn(0f, 1f)
    val y0 = (minOf(a.y, b.y) / h).coerceIn(0f, 1f)
    val x1 = (maxOf(a.x, b.x) / w).coerceIn(0f, 1f)
    val y1 = (maxOf(a.y, b.y) / h).coerceIn(0f, 1f)
    return RectF(x0, y0, x1, y1)
}

@Composable
private fun ZoneBox(rect: RectF, w: Float, h: Float, density: Float, color: Color, onRemove: (() -> Unit)?) {
    val left = (rect.left * w / density).dp
    val top = (rect.top * h / density).dp
    val width = (rect.width() * w / density).dp
    val height = (rect.height() * h / density).dp
    Box(
        Modifier.offset(left, top).size(width, height)
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White.copy(alpha = 0.25f))
            .border(2.dp, color, RoundedCornerShape(6.dp)),
    ) {
        if (onRemove != null) {
            Box(
                Modifier.align(Alignment.TopEnd).padding(2.dp).size(22.dp).clip(CircleShape).background(Color(0xFFFF3B30)).clickable(onClick = onRemove),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.Close, null, tint = Color.White, modifier = Modifier.size(14.dp)) }
        }
    }
}
