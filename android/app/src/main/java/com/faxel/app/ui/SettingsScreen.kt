package com.faxel.app.ui

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.os.LocaleListCompat
import com.faxel.app.R
import com.faxel.app.data.Prefs
import com.faxel.app.engine.Engine
import com.faxel.app.engine.Storage

private val languages = listOf(
    "" to R.string.lang_system, "fr" to R.string.lang_fr, "en" to R.string.lang_en,
    "es" to R.string.lang_es, "de" to R.string.lang_de, "ru" to R.string.lang_ru,
)

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val lang = AppCompatDelegate.getApplicationLocales().toLanguageTags().substringBefore('-')
    val engine = Engine.settings
    var rescanned by remember { mutableStateOf<Int?>(null) }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(Modifier.fillMaxSize().widthIn(max = 720.dp), contentPadding = PaddingValues(bottom = 32.dp)) {
            item { ScreenTitle(stringResource(R.string.tab_settings)) }

            item { Group(stringResource(R.string.general)) }
            item {
                Choice(stringResource(R.string.language), languages, lang) { tag ->
                    AppCompatDelegate.setApplicationLocales(
                        if (tag.isEmpty()) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(tag),
                    )
                    Engine.setLanguage(tag)
                }
            }
            item {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(stringResource(R.string.accent_color), color = Color.White, fontSize = 16.sp)
                    Spacer(Modifier.size(10.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(Prefs.accents) { hex ->
                            val selected = Prefs.accent.value.equals(hex, true)
                            Box(
                                Modifier.size(36.dp).clip(CircleShape).background(colorFromHex(hex))
                                    .border(if (selected) 3.dp else 0.dp, Color.White, CircleShape)
                                    .clickable { Prefs.accent.value = hex },
                            )
                        }
                    }
                }
            }

            item { Group(stringResource(R.string.downloads)) }
            item {
                Choice(stringResource(R.string.default_type), listOf("video" to R.string.video, "audio" to R.string.audio), Prefs.defaultMedia.value) {
                    Prefs.defaultMedia.value = it
                    DownloadModel.media = it
                }
            }
            item {
                val qualities = listOf(BEST, "2160p", "1440p", "1080p", "720p", "480p", "360p")
                ChoiceText(stringResource(R.string.default_quality), qualities.map { it to (if (it == BEST) stringResource(R.string.best) else it) }, Prefs.defaultQuality.value) {
                    Prefs.defaultQuality.value = it
                    DownloadModel.quality = it
                }
            }
            item {
                val max = engine.optInt("max_parallel", 2)
                ChoiceText(stringResource(R.string.parallel), (1..4).map { "$it" to "$it" }, "$max") { Engine.setSetting("max_parallel", it.toInt()) }
            }
            item { Toggle(stringResource(R.string.one_tap_share), stringResource(R.string.one_tap_share_hint), Prefs.oneTapShare.value) { Prefs.oneTapShare.value = it } }
            item { Toggle(stringResource(R.string.clean_titles), "", engine.optBoolean("clean_titles", true)) { Engine.setSetting("clean_titles", it) } }
            item { Toggle(stringResource(R.string.skip_duplicates), "", engine.optBoolean("skip_duplicates", true)) { Engine.setSetting("skip_duplicates", it) } }
            item { Toggle(stringResource(R.string.auto_retry), "", engine.optBoolean("auto_retry", true)) { Engine.setSetting("auto_retry", it) } }
            item { Toggle(stringResource(R.string.allow_av1), stringResource(R.string.allow_av1_hint), engine.optBoolean("allow_av1", false)) { Engine.setSetting("allow_av1", it) } }

            item { Group(stringResource(R.string.tab_browser)) }
            item { Toggle(stringResource(R.string.ask_download), stringResource(R.string.ask_download_hint), Prefs.askDownload.value) { Prefs.askDownload.value = it } }
            item { Toggle(stringResource(R.string.browser_cookies), stringResource(R.string.browser_cookies_hint), engine.optBoolean("use_browser_cookies", false)) { Engine.setSetting("use_browser_cookies", it) } }
            item {
                ChoiceText(
                    stringResource(R.string.search_engine),
                    listOf("google" to "Google", "duckduckgo" to "DuckDuckGo", "bing" to "Bing", "youtube" to "YouTube"),
                    Prefs.searchEngine.value,
                ) { Prefs.searchEngine.value = it }
            }

            item { Group(stringResource(R.string.player)) }
            item { Toggle(stringResource(R.string.auto_subtitles), stringResource(R.string.auto_subtitles_hint), Prefs.autoSubtitles.value) { Prefs.autoSubtitles.value = it } }
            item { Toggle(stringResource(R.string.auto_pip), "", Prefs.autoPip.value) { Prefs.autoPip.value = it } }

            item { Group(stringResource(R.string.storage)) }
            item {
                val full = Storage.hasFullAccess(context)
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(stringResource(R.string.storage_folder), color = Color.White, fontSize = 16.sp)
                    Text(Engine.root?.absolutePath ?: "—", color = Muted, fontSize = 13.sp)
                    if (!full) {
                        Text(stringResource(R.string.storage_private_hint), color = Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                        Text(
                            stringResource(R.string.storage_allow), color = accent, fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = 8.dp).clickable {
                                Storage.accessIntent(context)?.let { runCatching { context.startActivity(it) } }
                            },
                        )
                    } else if (!Storage.isPublic) {
                        Text(stringResource(R.string.storage_restart), color = accent, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
            item {
                Row2(stringResource(R.string.rescan), rescanned?.let { stringResource(R.string.n_added, it) } ?: "") {
                    Engine.rescan { rescanned = it }
                }
            }

            item { Group(stringResource(R.string.about)) }
            item { com.faxel.app.update.AppNameRow() }
            item { com.faxel.app.update.UpdateSettingsRow() }
            item {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(com.faxel.app.update.AppName.get(androidx.compose.ui.platform.LocalContext.current) + " " + com.faxel.app.update.Updater.currentVersion, color = Color.White, fontSize = 16.sp)
                    Text("Python ${Engine.python} · yt-dlp ${Engine.ytdlp}", color = Muted, fontSize = 13.sp)
                    Text(
                        stringResource(R.string.js_engine) + " : " + stringResource(if (Engine.javascript) R.string.yes else R.string.no),
                        color = Muted, fontSize = 13.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun Group(title: String) {
    Text(title.uppercase(), color = accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 4.dp))
}

@Composable
private fun Row2(title: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(value, color = Muted, fontSize = 15.sp)
        Spacer(Modifier.width(6.dp))
        Text("›", color = Muted, fontSize = 20.sp)
    }
}

@Composable
private fun Toggle(title: String, hint: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!value) }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 16.sp)
            if (hint.isNotBlank()) Text(hint, color = Muted, fontSize = 13.sp)
        }
        Spacer(Modifier.width(8.dp))
        Switch(value, onChange)
    }
}

@Composable
private fun Choice(title: String, options: List<Pair<String, Int>>, selected: String, onSelect: (String) -> Unit) {
    ChoiceText(title, options.map { it.first to stringResource(it.second) }, selected, onSelect)
}

@Composable
private fun ChoiceText(title: String, options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val label = options.firstOrNull { it.first == selected }?.second ?: options.first().second
    Box {
        Row2(title, label) { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            options.forEach { (key, text) ->
                DropdownMenuItem(text = { Text((if (key == selected) "✓ " else "") + text) }, onClick = { onSelect(key); open = false })
            }
        }
    }
}
