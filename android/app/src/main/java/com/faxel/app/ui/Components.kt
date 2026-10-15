package com.faxel.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.faxel.app.R
import java.io.File
import java.util.Locale

fun formatTime(seconds: Double?): String {
    val total = (seconds ?: 0.0).toLong().coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

fun formatMs(ms: Long) = formatTime(ms / 1000.0)

fun formatSize(bytes: Double?): String {
    val b = bytes ?: return ""
    if (b <= 0) return ""
    val units = listOf("o", "Ko", "Mo", "Go")
    var value = b
    var unit = 0
    while (value >= 1024 && unit < units.size - 1) {
        value /= 1024
        unit++
    }
    return if (unit >= 2) String.format(Locale.getDefault(), "%.1f %s", value, units[unit]) else "${value.toInt()} ${units[unit]}"
}

/**
 * Miniature : image en ligne si elle existe, sinon première image de la vidéo,
 * sinon un dégradé avec une icône.
 */
@Composable
fun Thumb(
    url: String?,
    path: String?,
    size: Dp? = null,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(10.dp),
    audio: Boolean = false,
    folder: Boolean = false,
) {
    val seed = path ?: url ?: ""
    val base = if (size != null) modifier.size(size) else modifier
    Box(
        base.clip(shape).background(Brush.linearGradient(gradientFor(seed))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            when {
                folder -> Icons.Rounded.Folder
                audio -> Icons.Rounded.MusicNote
                else -> Icons.Rounded.Movie
            },
            null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(28.dp),
        )
        val model: Any? = when {
            !url.isNullOrBlank() -> url
            !audio && !folder && !path.isNullOrBlank() && File(path).isFile -> File(path)
            else -> null
        }
        if (model != null) {
            AsyncImage(model = model, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

@Composable
fun ScreenTitle(text: String, modifier: Modifier = Modifier, trailing: @Composable () -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().statusBarsPadding().padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        trailing()
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = modifier.padding(horizontal = 16.dp, vertical = 10.dp))
}

@Composable
fun EmptyState(title: String, subtitle: String = "", icon: androidx.compose.ui.graphics.vector.ImageVector = Icons.Rounded.Movie) {
    Column(Modifier.fillMaxWidth().padding(36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, tint = Muted, modifier = Modifier.size(52.dp))
        Spacer(Modifier.size(12.dp))
        Text(title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        if (subtitle.isNotBlank()) {
            Spacer(Modifier.size(6.dp))
            Text(subtitle, color = Muted, fontSize = 14.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

@Composable
fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text,
        color = if (selected) Color.White else Color.White.copy(alpha = 0.8f),
        fontSize = 14.sp,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (selected) accent else Surface2)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
fun NameDialog(title: String, initial: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(value = text, onValueChange = { text = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onConfirm(text.trim()) }) { Text(stringResource(R.string.ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.clip(RoundedCornerShape(18.dp)).background(Surface1).padding(14.dp)) { content() }
}

@Composable
fun RowSpacer() = Spacer(Modifier.width(12.dp))

val gap = Arrangement.spacedBy(10.dp)

/** Empêche les touchers de passer à ce qui est dessous (écrans superposés). */
fun Modifier.blockTouches(): Modifier = this.pointerInput(Unit) { detectTapGestures { } }
