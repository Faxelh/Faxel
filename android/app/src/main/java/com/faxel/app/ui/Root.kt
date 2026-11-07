package com.faxel.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.SmartDisplay
import androidx.compose.material.icons.rounded.Storefront
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
import androidx.compose.ui.draw.graphicsLayer
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
import coil.compose.AsyncImage

enum class Tab(val icon: ImageVector, val label: Int) {
    Home(Icons.Rounded.Home, R.string.tab_home),
    Library(Icons.Rounded.VideoLibrary, R.string.tab_library),
    Download(Icons.Rounded.Download, R.string.tab_download),
    Settings(Icons.Rounded.Settings, R.string.tab_settings),
    Browser(Icons.Rounded.Language, R.string.tab_browser),
}

/** Largeur de l'écran : téléphone (compact) ou tablette / téléphone à l'horizontale. */
object Layout {
    var wide by mutableStateOf(false)
}

@Composable
fun FaxelRoot() {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    var audioOpen by rememberSaveable { mutableStateOf(false) }
    var searchOpen by rememberSaveable { mutableStateOf(false) }
    var compressionOpen by rememberSaveable { mutableStateOf(false) }
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
                            Tab.Home -> HomeScreen(onNavigate = { tab = it }, onSearch = { searchOpen = true }, onCompression = { compressionOpen = true })
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
                    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
                        if (AudioConnection.current != null) MiniPlayer(onOpen = { audioOpen = true })
                        val selectedDockIndex = when {
                            compressionOpen -> 3
                            tab == Tab.Browser -> 5
                            tab == Tab.Settings -> 4
                            else -> when (tab) {
                                Tab.Home -> 0
                                Tab.Library -> 1
                                Tab.Download -> 2
                                else -> 0
                            }
                        }
                        BoxWithConstraints(
                            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp)
                                .clip(RoundedCornerShape(50)).background(Surface1).padding(4.dp).height(52.dp),
                        ) {
                            val itemWidth = maxWidth / 6f
                            val indicatorX by animateDpAsState(itemWidth * selectedDockIndex.toFloat() + 2.dp, label = "dockSelection")
                            Box(Modifier.align(Alignment.CenterStart).offset(x = indicatorX).width(itemWidth - 4.dp).height(48.dp)
                                .clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.12f)))
                            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                                DockIcon(Icons.Rounded.Home, tab == Tab.Home && !compressionOpen, stringResource(R.string.tab_home), Modifier.weight(1f)) { compressionOpen = false; tab = Tab.Home; searchOpen = false }
                                DockIcon(Icons.Rounded.SmartDisplay, tab == Tab.Library && !compressionOpen, stringResource(R.string.tab_library), Modifier.weight(1f)) { compressionOpen = false; tab = Tab.Library; searchOpen = false }
                                DockIcon(Icons.Rounded.Storefront, tab == Tab.Download && !compressionOpen, stringResource(R.string.tab_download), Modifier.weight(1f), Engine.jobs.count { it.active }) { compressionOpen = false; tab = Tab.Download; searchOpen = false }
                                DockIcon(Icons.Rounded.AutoFixHigh, compressionOpen, "Compresser", Modifier.weight(1f)) { compressionOpen = true; searchOpen = false }
                                DockIcon(Icons.Rounded.AccountCircle, tab == Tab.Settings && !compressionOpen, stringResource(R.string.tab_settings), Modifier.weight(1f), photo = Prefs.profilePhoto.value) { compressionOpen = false; tab = Tab.Settings; searchOpen = false }
                                DockIcon(Icons.Rounded.Language, tab == Tab.Browser && !compressionOpen, stringResource(R.string.tab_browser), Modifier.weight(1f)) { compressionOpen = false; tab = Tab.Browser; searchOpen = false }
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
        if (compressionOpen) CompressionScreen(onClose = { compressionOpen = false })
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

@Composable
private fun DockIcon(icon: ImageVector, selected: Boolean, label: String, modifier: Modifier,
                     badge: Int = 0, photo: String = "", onClick: () -> Unit) {
    Box(modifier.padding(2.dp).fillMaxWidth().height(52.dp).clip(RoundedCornerShape(50))
        .clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        if (photo.isNotBlank()) AsyncImage(photo, label, contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            modifier = Modifier.size(30.dp).clip(androidx.compose.foundation.shape.CircleShape))
        else Icon(icon, label, tint = Color.White, modifier = Modifier.size(if (selected) 28.dp else 27.dp).graphicsLayer {
            val scale = if (selected) 1.04f else 1f
            scaleX = scale; scaleY = scale
        })
        if (badge > 0) {
            Text(if (badge > 99) "99+" else "$badge", color = Color.White, fontSize = 10.sp,
                modifier = Modifier.align(Alignment.TopEnd).clip(RoundedCornerShape(50)).background(Color(0xFFE9233C)).padding(horizontal = 5.dp, vertical = 2.dp))
        }
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
