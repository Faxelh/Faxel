package com.faxel.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.faxel.app.data.Prefs

fun colorFromHex(hex: String): Color {
    val value = hex.trim().removePrefix("#").toLongOrNull(16) ?: 0x7C5CFFL
    return Color(0xFF000000L or value)
}

val accent: Color get() = colorFromHex(Prefs.accent.value)

val Surface1 = Color(0xFF15151B)
val Surface2 = Color(0xFF1E1E26)
val Muted = Color(0xFF9A9AA8)

val gradients = listOf(
    listOf(Color(0xFF7C5CFF), Color(0xFFFF2D60)),
    listOf(Color(0xFF0A84FF), Color(0xFF00C7BE)),
    listOf(Color(0xFFFF9500), Color(0xFFFF375F)),
    listOf(Color(0xFF34C759), Color(0xFF30B0C7)),
    listOf(Color(0xFFBF5AF2), Color(0xFF5E5CE6)),
)

fun gradientFor(seed: String): List<Color> = gradients[(seed.hashCode() and 0x7fffffff) % gradients.size]

@Composable
fun FaxelTheme(content: @Composable () -> Unit) {
    val main = accent
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = main,
            secondary = main,
            tertiary = main,
            background = Color(0xFF0B0B0F),
            surface = Surface1,
            surfaceVariant = Surface2,
            surfaceContainer = Surface1,
            surfaceContainerHigh = Surface2,
            surfaceContainerHighest = Color(0xFF26262F),
            onBackground = Color.White,
            onSurface = Color.White,
            onPrimary = Color.White,
        ),
        content = content,
    )
}
