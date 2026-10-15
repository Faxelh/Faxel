package com.faxel.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.app.R
import com.faxel.app.data.Prefs
import com.faxel.app.engine.Engine
import com.faxel.app.engine.Storage
import com.faxel.app.playback.AudioConnection
import com.faxel.app.playback.VideoState
import java.io.File

enum class Tab(val icon: ImageVector, val label: Int) {
    Download(Icons.Rounded.Download, R.string.tab_download),
    Library(Icons.Rounded.VideoLibrary, R.string.tab_library),
    Browser(Icons.Rounded.Language, R.string.tab_browser),
    Settings(Icons.Rounded.Settings, R.string.tab_settings),
}

/** Largeur de l'écran : téléphone (compact) ou tablette / téléphone à l'horizontale. */
object Layout {
    var wide by mutableStateOf(false)
}

@Composable
fun FaxelRoot() {
    var tab by rememberSaveable { mutableStateOf(Tab.Download) }
    var audioOpen by rememberSaveable { mutableStateOf(false) }
    var searchOpen by rememberSaveable { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current

    // Image dans l'image : seule la vidéo s'affiche.
    if (VideoState.inPip && VideoState.open) {
        VideoScreen(onClose = { VideoState.close() })
        return
    }

    LaunchedEffect(Engine.pendingLink) {
        if (Engine.pendingLink != null) {
            tab = Tab.Download
            searchOpen = false
        }
    }

    val notice = Engine.notice
    val openLabel = stringResource(R.string.open)
    val downloadedLabel = stringResource(R.string.downloaded)
    LaunchedEffect(notice) {
        val n = notice ?: return@LaunchedEffect
        val text = if (n.error) n.text else "$downloadedLabel : ${n.text}"
        val result = snackbar.showSnackbar(text, actionLabel = if (n.path.isNullOrBlank() || n.error) null else openLabel, withDismissAction = true)
        if (result == SnackbarResult.ActionPerformed && n.path != null) {
            val entry = Engine.entry(n.path)
            if (entry != null) openEntry(context, entry, listOf(entry)) { audioOpen = true }
            else {
                val file = File(n.path)
                if (file.isFile) VideoState.play(context, listOf(file), 0)
            }
        }
    }

    BackHandler(enabled = audioOpen || searchOpen || (tab == Tab.Browser && Browser.canGoBack)) {
        when {
            audioOpen -> audioOpen = false
            searchOpen -> searchOpen = false
            else -> Browser.back()
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color(0xFF0B0B0F))) {
        val wide = maxWidth >= 600.dp
        LaunchedEffect(wide) { Layout.wide = wide }
        val content: @Composable (Modifier) -> Unit = { modifier ->
            Box(modifier) {
                // Le navigateur reste en place (page, vidéo, connexion gardées) ; les autres
                // onglets s'affichent par-dessus.
                BrowserScreen(onDownload = { tab = Tab.Download }, visible = tab == Tab.Browser && !searchOpen)
                if (tab != Tab.Browser) {
                    Box(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).blockTouches()) {
                        when (tab) {
                            Tab.Download -> DownloadScreen(onSearch = { searchOpen = true })
                            Tab.Library -> LibraryScreen(onOpenAudio = { audioOpen = true })
                            Tab.Settings -> SettingsScreen()
                            Tab.Browser -> {}
                        }
                    }
                }
                if (searchOpen) SearchScreen(onClose = { searchOpen = false })
            }
        }

        if (wide) {
            Row(Modifier.fillMaxSize()) {
                NavigationRail(containerColor = Surface1, modifier = Modifier.fillMaxHeight()) {
                    Spacer(Modifier.height(24.dp))
                    Tab.entries.forEach { item ->
                        NavigationRailItem(
                            selected = tab == item,
                            onClick = { tab = item; searchOpen = false },
                            icon = { TabIcon(item) },
                            label = { Text(stringResource(item.label), fontSize = 12.sp) },
                            colors = NavigationRailItemDefaults.colors(indicatorColor = accent.copy(alpha = 0.25f)),
                        )
                    }
                }
                // Tablette / paysage : rien sous la barre de navigation d'Android.
                Column(Modifier.weight(1f).fillMaxHeight().navigationBarsPadding()) {
                    content(Modifier.weight(1f).fillMaxWidth())
                    if (AudioConnection.current != null) {
                        MiniPlayer(onOpen = { audioOpen = true })
                    }
                }
            }
        } else {
            Scaffold(
                containerColor = Color(0xFF0B0B0F),
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
                bottomBar = {
                    Column(Modifier.background(Surface1)) {
                        if (AudioConnection.current != null) MiniPlayer(onOpen = { audioOpen = true })
                        NavigationBar(containerColor = Surface1, tonalElevation = 0.dp) {
                            Tab.entries.forEach { item ->
                                NavigationBarItem(
                                    selected = tab == item,
                                    onClick = { tab = item; searchOpen = false },
                                    icon = { TabIcon(item) },
                                    label = { Text(stringResource(item.label), fontSize = 11.sp, maxLines = 1) },
                                    colors = NavigationBarItemDefaults.colors(indicatorColor = accent.copy(alpha = 0.25f)),
                                )
                            }
                        }
                    }
                },
            ) { padding ->
                content(Modifier.fillMaxSize().padding(padding))
            }
        }

        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(bottom = if (wide) 24.dp else 140.dp))

        AnimatedVisibility(
            visible = audioOpen && AudioConnection.current != null,
            enter = slideInVertically(tween(300)) { it },
            exit = slideOutVertically(tween(250)) { it },
        ) {
            AudioScreen(onClose = { audioOpen = false })
        }

        if (VideoState.open) VideoScreen(onClose = { VideoState.close() })
    }

    StorageAccessDialog()
    com.faxel.app.update.UpdateCheck()
}

@Composable
private fun TabIcon(item: Tab) {
    val running = Engine.jobs.count { it.active }
    if (item == Tab.Download && running > 0) {
        BadgedBox(badge = { Badge { Text("$running") } }) { Icon(item.icon, null) }
    } else {
        Icon(item.icon, null)
    }
}

/** Au premier lancement : proposer le dossier « Faxel » visible dans tout le téléphone. */
@Composable
private fun StorageAccessDialog() {
    val context = LocalContext.current
    var show by remember { mutableStateOf(!Prefs.askedStorage.value && !Storage.hasFullAccess(context)) }
    if (!show) return
    AlertDialog(
        onDismissRequest = { show = false; Prefs.askedStorage.value = true },
        title = { Text(stringResource(R.string.storage_title)) },
        text = { Text(stringResource(R.string.storage_text)) },
        confirmButton = {
            TextButton(onClick = {
                show = false
                Prefs.askedStorage.value = true
                Storage.accessIntent(context)?.let { runCatching { context.startActivity(it) } }
            }) { Text(stringResource(R.string.storage_allow)) }
        },
        dismissButton = {
            TextButton(onClick = { show = false; Prefs.askedStorage.value = true }) { Text(stringResource(R.string.later)) }
        },
    )
}

@Composable
fun MiniPlayer(onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val entry = AudioConnection.current ?: return
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Surface2)
            .clickable(onClick = onOpen)
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Thumb(entry.thumbnail, entry.path, 44.dp, audio = true)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(entry.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (entry.uploader.isNotBlank()) Text(entry.uploader, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onClick = { AudioConnection.toggle() }) {
            Icon(if (AudioConnection.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(30.dp))
        }
        IconButton(onClick = { AudioConnection.next() }) {
            Icon(Icons.Rounded.SkipNext, null, tint = Color.White)
        }
    }
}
