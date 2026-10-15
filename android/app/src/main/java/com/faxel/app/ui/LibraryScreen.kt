package com.faxel.app.ui

import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.faxel.app.R
import com.faxel.app.data.Entry
import com.faxel.app.data.Subtitles
import com.faxel.app.engine.Engine
import com.faxel.app.playback.AudioConnection
import com.faxel.app.playback.VideoState
import java.io.File

enum class Section(val label: Int) {
    Videos(R.string.videos), Music(R.string.music), Favorites(R.string.favorites), Playlists(R.string.playlists), Photos(R.string.photos)
}

object LibraryModel {
    var section by mutableStateOf(Section.Videos)
    var folder by mutableStateOf<String?>(null)
    var playlist by mutableStateOf<String?>(null)
    var gallery by mutableStateOf<String?>(null)
    var watermark by mutableStateOf<String?>(null)
    var query by mutableStateOf("")
    var searching by mutableStateOf(false)
    /** Sélection de plusieurs éléments (clé = chemin du fichier). */
    val selection = SelectionState()
}

/** Fichiers à exporter pour un élément (les photos d'une publication sont dans un dossier). */
private fun filesOf(entry: Entry): List<File> =
    if (entry.isFolder) {
        File(entry.path).listFiles()?.filter { it.isFile && it.extension.lowercase() in setOf("jpg", "jpeg", "png", "webp", "gif", "mp4") }
            ?.sortedBy { it.name } ?: emptyList()
    } else {
        listOf(File(entry.path)).filter { it.isFile }
    }

/** Ouvre un élément : vidéo (avec les épisodes du même dossier), son (avec la liste), photos. */
fun openEntry(context: Context, entry: Entry, list: List<Entry>, onAudio: () -> Unit) {
    when {
        entry.isFolder -> LibraryModel.gallery = entry.path
        entry.isAudio -> {
            val sounds = list.filter { it.isAudio && it.exists }
            AudioConnection.play(sounds.ifEmpty { listOf(entry) }, sounds.indexOfFirst { it.path == entry.path }.coerceAtLeast(0))
            onAudio()
        }
        else -> {
            val file = File(entry.path)
            val siblings = file.parentFile?.listFiles()?.filter { it.isFile && it.extension.lowercase() in com.faxel.app.data.VIDEO_EXT }
                ?.sortedWith { a, b -> Subtitles.episodeOrder(a, b) } ?: listOf(file)
            val files = siblings.ifEmpty { listOf(file) }
            VideoState.play(context, files, files.indexOfFirst { it.absolutePath == file.absolutePath }.coerceAtLeast(0))
        }
    }
}

fun share(context: Context, entry: Entry) {
    runCatching {
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", File(entry.path))
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = if (entry.isAudio) "audio/*" else "video/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, entry.title))
    }
}

@Composable
fun LibraryScreen(onOpenAudio: () -> Unit) {
    val model = LibraryModel
    val context = LocalContext.current
    val selection = model.selection
    BackHandler(enabled = model.folder != null || model.playlist != null || model.gallery != null || selection.active) {
        when {
            selection.active -> selection.finish()
            model.gallery != null -> model.gallery = null
            model.playlist != null -> model.playlist = null
            else -> model.folder = null
        }
    }
    model.gallery?.let { path ->
        Gallery(path) { model.gallery = null }
        return
    }
    model.watermark?.let { path ->
        WatermarkScreen(File(path)) { model.watermark = null }
        return
    }

    val query = model.query.trim()
    val all = Engine.entries.filter { it.exists }.filter {
        query.isEmpty() || it.title.contains(query, true) || it.uploader.contains(query, true) || it.folder.contains(query, true)
    }
    val minCell = if (Layout.wide) 200.dp else 160.dp

    // Ce que « Tout sélectionner » prend dans la vue actuelle.
    val selectable = when (model.section) {
        Section.Videos -> all.filter { it.isVideo && (model.folder == null || it.folderPath == model.folder) }
        Section.Music -> all.filter { it.isAudio }
        Section.Favorites -> all.filter { it.path in Engine.favorites }
        Section.Playlists -> model.playlist?.let { id ->
            val byPath = all.associateBy { it.path }
            Engine.playlists.firstOrNull { it.id == id }?.paths?.mapNotNull { byPath[it] }
        } ?: emptyList()
        Section.Photos -> all.filter { it.isFolder }
    }
    LaunchedEffect(model.section, model.folder, model.playlist) { selection.finish() }

    Box(Modifier.fillMaxSize()) {
    LazyVerticalGrid(
        GridCells.Adaptive(minCell),
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = if (selection.active) 150.dp else 24.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        full { Header(context, canSelect = selectable.isNotEmpty()) }
        when (model.section) {
            Section.Videos -> videos(all, context)
            Section.Music -> list(all.filter { it.isAudio }, context, onOpenAudio, showPlayAll = true)
            Section.Favorites -> list(all.filter { it.path in Engine.favorites }, context, onOpenAudio, showPlayAll = false)
            Section.Playlists -> playlists(all, context, onOpenAudio)
            Section.Photos -> photos(all)
        }
    }
    if (selection.active) {
        LibrarySelectionBar(selectable, Modifier.align(Alignment.BottomCenter))
    }
    }
}

/** Barre de sélection de la bibliothèque : Galerie, Dossier, Partager, Supprimer. */
@Composable
private fun LibrarySelectionBar(selectable: List<Entry>, modifier: Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val selection = LibraryModel.selection
    val chosen = selectable.filter { selection.isSelected(it.path) }
    var confirm by remember { mutableStateOf(false) }
    val galleryDone = stringResource(R.string.sel_gallery_done)
    val folderDone = stringResource(R.string.sel_folder_done)
    val working = stringResource(R.string.sel_working)
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        if (tree != null) {
            val files = chosen.flatMap { filesOf(it) }
            Toast.makeText(context, working, Toast.LENGTH_SHORT).show()
            scope.launch {
                val count = Exporter.toFolder(context, tree, files)
                Toast.makeText(context, folderDone.format(count), Toast.LENGTH_LONG).show()
                selection.finish()
            }
        }
    }
    Box(modifier) {
        SelectionBar(
            count = chosen.size,
            total = selectable.size,
            onAll = { selection.setAll(selectable.map { it.path }, it) },
            onDone = { selection.finish() },
            actions = listOf(
                SelectionAction(stringResource(R.string.sel_gallery), Icons.Rounded.PhotoLibrary, enabled = chosen.isNotEmpty()) {
                    val files = chosen.flatMap { filesOf(it) }
                    Toast.makeText(context, working, Toast.LENGTH_SHORT).show()
                    scope.launch {
                        val count = Exporter.toGallery(context, files)
                        Toast.makeText(context, galleryDone.format(count), Toast.LENGTH_LONG).show()
                        selection.finish()
                    }
                },
                SelectionAction(stringResource(R.string.sel_folder), Icons.Rounded.Folder, enabled = chosen.isNotEmpty()) {
                    folderPicker.launch(null)
                },
                SelectionAction(stringResource(R.string.sel_share), Icons.Rounded.Share, enabled = chosen.isNotEmpty()) {
                    Exporter.share(context, chosen.flatMap { filesOf(it) })
                },
                SelectionAction(stringResource(R.string.sel_delete), Icons.Rounded.Delete, enabled = chosen.isNotEmpty(), destructive = true) {
                    confirm = true
                },
            ),
        )
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.sel_delete_title, chosen.size)) },
            text = { Text(stringResource(R.string.sel_delete_text)) },
            confirmButton = {
                TextButton(onClick = {
                    chosen.forEach { Engine.delete(it) }
                    Toast.makeText(context, context.getString(R.string.sel_deleted, chosen.size), Toast.LENGTH_SHORT).show()
                    confirm = false
                    selection.finish()
                }) { Text(stringResource(R.string.sel_delete), color = Color(0xFFFF5252)) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private fun LazyGridScope.full(content: @Composable () -> Unit) {
    item(span = { GridItemSpan(maxLineSpan) }) { content() }
}

@Composable
private fun Header(context: Context, canSelect: Boolean) {
    val model = LibraryModel
    Column {
        val title = when {
            model.folder != null -> File(model.folder!!).name
            model.playlist != null -> Engine.playlists.firstOrNull { it.id == model.playlist }?.name ?: ""
            else -> stringResource(R.string.tab_library)
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (model.folder != null || model.playlist != null) {
                IconButton(onClick = { model.folder = null; model.playlist = null }) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = accent)
                }
            }
            Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(start = 4.dp))
            IconButton(onClick = { model.searching = !model.searching; if (!model.searching) model.query = "" }) {
                Icon(Icons.Rounded.Search, null, tint = accent)
            }
            if (canSelect || model.selection.active) {
                IconButton(onClick = { if (model.selection.active) model.selection.finish() else model.selection.start() }) {
                    Icon(if (model.selection.active) Icons.Rounded.Close else Icons.Rounded.Checklist, null, tint = accent)
                }
            }
            IconButton(onClick = { Engine.rescan() }) { Icon(Icons.Rounded.Refresh, null, tint = accent) }
        }
        if (model.searching) {
            OutlinedTextField(
                value = model.query, onValueChange = { model.query = it }, singleLine = true,
                placeholder = { Text(stringResource(R.string.search_library)) },
                trailingIcon = { IconButton(onClick = { model.query = ""; model.searching = false }) { Icon(Icons.Rounded.Close, null) } },
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Surface1, focusedContainerColor = Surface1),
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            )
        }
        if (model.folder == null && model.playlist == null) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Section.entries.forEach { section ->
                    Chip(stringResource(section.label), model.section == section) { model.section = section }
                }
            }
        }
    }
}

// MARK: Vidéos rangées par dossier

private fun LazyGridScope.videos(all: List<Entry>, context: Context) {
    val videos = all.filter { it.isVideo }
    val model = LibraryModel
    if (videos.isEmpty()) {
        full { EmptyState(stringResourceSafe(R.string.no_videos), stringResourceSafe(R.string.no_videos_hint)) }
        return
    }
    val folders = videos.groupBy { it.folderPath }
    val open = model.folder
    if (open == null && folders.size > 1 && model.query.isBlank()) {
        items(folders.entries.sortedByDescending { e -> e.value.maxOf { it.date } }.toList(), key = { "f-" + it.key }) { (path, list) ->
            Column(Modifier.clip(RoundedCornerShape(14.dp)).clickable { model.folder = path }) {
                Box {
                    val first = list.first()
                    Thumb(first.thumbnail, first.path, modifier = Modifier.fillMaxWidth().aspectRatio(16f / 10f))
                    Row(
                        Modifier.align(Alignment.BottomEnd).padding(6.dp).clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.6f))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Rounded.Folder, null, tint = Color.White, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("${list.size}", color = Color.White, fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text(File(path).name, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        return
    }
    val shown = (if (open != null) videos.filter { it.folderPath == open } else videos)
        .sortedWith { a, b -> Subtitles.episodeOrder(File(a.path), File(b.path)) }
    items(shown, key = { "v-" + it.path }) { entry -> VideoCard(entry, shown, context) }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VideoCard(entry: Entry, list: List<Entry>, context: Context) {
    var menu by remember { mutableStateOf(false) }
    val selection = LibraryModel.selection
    Column(
        Modifier.clip(RoundedCornerShape(14.dp)).combinedClickable(
            onClick = { if (selection.active) selection.toggle(entry.path) else openEntry(context, entry, list) {} },
            onLongClick = { if (selection.active) selection.toggle(entry.path) else selection.start(entry.path) },
        ),
    ) {
        Box {
            Thumb(entry.thumbnail, entry.path, modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f))
            if (selection.active) {
                SelectionCheck(selection.isSelected(entry.path), Modifier.align(Alignment.TopStart).padding(6.dp))
            }
            entry.duration?.takeIf { it > 0 }?.let {
                Text(
                    formatTime(it), color = Color.White, fontSize = 11.sp,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp).clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.65f)).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
            if (entry.path in Engine.favorites) {
                Icon(Icons.Rounded.Favorite, null, tint = accent, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(18.dp))
            }
        }
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f).padding(top = 6.dp)) {
                Text(entry.title, color = Color.White, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                val sub = listOf(entry.platformName, formatSize(entry.filesize)).filter { it.isNotBlank() }.joinToString(" · ")
                if (sub.isNotBlank()) Text(sub, color = Muted, fontSize = 12.sp, maxLines = 1)
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.size(32.dp)) { Icon(Icons.Rounded.MoreVert, null, tint = Muted) }
                EntryMenu(entry, menu) { menu = false }
            }
        }
    }
}

// MARK: Listes (musique, favoris, playlist)

private fun LazyGridScope.list(entries: List<Entry>, context: Context, onAudio: () -> Unit, showPlayAll: Boolean, playlistId: String? = null) {
    if (entries.isEmpty()) {
        full { EmptyState(stringResourceSafe(R.string.nothing_here), "", Icons.Rounded.MusicNote) }
        return
    }
    val sounds = entries.filter { it.isAudio }
    if (showPlayAll && sounds.isNotEmpty()) {
        full {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { AudioConnection.play(sounds); onAudio() }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Surface2, contentColor = accent),
                ) { Icon(Icons.Rounded.PlayArrow, null); Spacer(Modifier.width(4.dp)); Text(stringResourceSafe(R.string.play_all)) }
                Button(
                    onClick = { AudioConnection.play(sounds, shuffled = true); onAudio() }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Surface2, contentColor = accent),
                ) { Icon(Icons.Rounded.Shuffle, null); Spacer(Modifier.width(4.dp)); Text(stringResourceSafe(R.string.shuffle)) }
            }
        }
    }
    items(entries, key = { "l-" + it.path }, span = { GridItemSpan(maxLineSpan) }) { entry ->
        EntryRow(entry, entries, context, onAudio, playlistId)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryRow(entry: Entry, list: List<Entry>, context: Context, onAudio: () -> Unit, playlistId: String?) {
    var menu by remember { mutableStateOf(false) }
    val playing = AudioConnection.currentPath == entry.path
    val selection = LibraryModel.selection
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).combinedClickable(
            onClick = { if (selection.active) selection.toggle(entry.path) else openEntry(context, entry, list, onAudio) },
            onLongClick = { if (selection.active) selection.toggle(entry.path) else selection.start(entry.path) },
        ).padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selection.active) {
            SelectionCheck(selection.isSelected(entry.path))
            Spacer(Modifier.width(10.dp))
        }
        Thumb(entry.thumbnail, entry.path, modifier = Modifier.width(if (entry.isAudio) 52.dp else 92.dp).aspectRatio(if (entry.isAudio) 1f else 16f / 9f), audio = entry.isAudio)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(entry.title, color = if (playing) accent else Color.White, fontWeight = if (playing) FontWeight.Bold else FontWeight.Medium,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = listOf(entry.uploader, entry.duration?.takeIf { it > 0 }?.let { formatTime(it) } ?: "", formatSize(entry.filesize))
                .filter { it.isNotBlank() }.joinToString(" · ")
            Text(sub, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (entry.path in Engine.favorites) Icon(Icons.Rounded.Favorite, null, tint = accent, modifier = Modifier.size(16.dp))
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, null, tint = Muted) }
            EntryMenu(entry, menu, playlistId) { menu = false }
        }
    }
}

@Composable
private fun EntryMenu(entry: Entry, open: Boolean, playlistId: String? = null, onClose: () -> Unit) {
    val context = LocalContext.current
    var picking by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    DropdownMenu(expanded = open, onDismissRequest = onClose) {
        if (entry.isAudio) {
            DropdownMenuItem(text = { Text(stringResource(R.string.play_next)) }, leadingIcon = { Icon(Icons.Rounded.SkipNext, null) },
                onClick = { AudioConnection.playNext(entry); onClose() })
        }
        val fav = entry.path in Engine.favorites
        DropdownMenuItem(
            text = { Text(stringResource(if (fav) R.string.remove_favorite else R.string.add_favorite)) },
            leadingIcon = { Icon(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null) },
            onClick = { Engine.toggleFavorite(entry); onClose() },
        )
        DropdownMenuItem(text = { Text(stringResource(R.string.add_to_playlist)) }, leadingIcon = { Icon(Icons.Rounded.MusicNote, null) },
            onClick = { picking = true; onClose() })
        if (playlistId != null) {
            DropdownMenuItem(text = { Text(stringResource(R.string.remove_from_playlist)) }, leadingIcon = { Icon(Icons.Rounded.Close, null) },
                onClick = { Engine.removeFromPlaylist(playlistId, entry.path); onClose() })
        }
        DropdownMenuItem(text = { Text(stringResource(R.string.share)) }, leadingIcon = { Icon(Icons.Rounded.Share, null) },
            onClick = { share(context, entry); onClose() })
        if (entry.isVideo) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.wm_title) + "…") },
                leadingIcon = { Icon(Icons.Rounded.AutoFixHigh, null) },
                onClick = { LibraryModel.watermark = entry.path; onClose() },
            )
        }
        DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, leadingIcon = { Icon(Icons.Rounded.Delete, null) },
            onClick = { deleting = true; onClose() })
    }
    if (picking) PlaylistPicker(entry) { picking = false }
    if (deleting) {
        AlertDialog(
            onDismissRequest = { deleting = false },
            title = { Text(stringResource(R.string.delete_title)) },
            text = { Text(entry.title) },
            confirmButton = { TextButton(onClick = { Engine.delete(entry); deleting = false }) { Text(stringResource(R.string.delete), color = Color(0xFFFF6B6B)) } },
            dismissButton = { TextButton(onClick = { deleting = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun PlaylistPicker(entry: Entry, onDismiss: () -> Unit) {
    var creating by remember { mutableStateOf(false) }
    if (creating) {
        NameDialog(stringResource(R.string.new_playlist), "", onDismiss) { name ->
            Engine.createPlaylist(name) { id -> if (id.isNotBlank()) Engine.addToPlaylist(id, entry) }
            onDismiss()
        }
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.add_to_playlist)) },
        text = {
            Column {
                Text("+ " + stringResource(R.string.new_playlist), color = accent, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth().clickable { creating = true }.padding(vertical = 10.dp))
                Engine.playlists.forEach { list ->
                    Text(list.name, modifier = Modifier.fillMaxWidth().clickable { Engine.addToPlaylist(list.id, entry); onDismiss() }.padding(vertical = 10.dp))
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

// MARK: Playlists

private fun LazyGridScope.playlists(all: List<Entry>, context: Context, onAudio: () -> Unit) {
    val model = LibraryModel
    val open = model.playlist
    if (open != null) {
        val chosen = Engine.playlists.firstOrNull { it.id == open }
        if (chosen == null) {
            full { EmptyState(stringResourceSafe(R.string.nothing_here)) }
            return
        }
        full { PlaylistActions(chosen.id, chosen.name) }
        val byPath = all.associateBy { it.path }
        list(chosen.paths.mapNotNull { byPath[it] }, context, onAudio, showPlayAll = true, playlistId = chosen.id)
        return
    }
    full { NewPlaylistRow() }
    if (Engine.playlists.isEmpty()) {
        full { EmptyState(stringResourceSafe(R.string.no_playlists), "", Icons.Rounded.MusicNote) }
        return
    }
    items(Engine.playlists, key = { "p-" + it.id }) { list ->
        val first = list.paths.firstOrNull()?.let { path -> all.firstOrNull { it.path == path } }
        Column(Modifier.clip(RoundedCornerShape(14.dp)).clickable { model.playlist = list.id }) {
            Thumb(first?.thumbnail, first?.path, modifier = Modifier.fillMaxWidth().aspectRatio(1f), audio = first?.isAudio ?: true)
            Spacer(Modifier.height(6.dp))
            Text(list.name, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(stringResourceSafe(R.string.n_items, list.paths.size), color = Muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun NewPlaylistRow() {
    var creating by remember { mutableStateOf(false) }
    Text("+ " + stringResource(R.string.new_playlist), color = accent, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.clickable { creating = true }.padding(vertical = 8.dp))
    if (creating) NameDialog(stringResource(R.string.new_playlist), "", { creating = false }) { Engine.createPlaylist(it); creating = false }
}

@Composable
private fun PlaylistActions(id: String, name: String) {
    var renaming by remember { mutableStateOf(false) }
    Row {
        TextButton(onClick = { renaming = true }) { Icon(Icons.Rounded.Edit, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.rename)) }
        TextButton(onClick = { Engine.deletePlaylist(id); LibraryModel.playlist = null }) {
            Icon(Icons.Rounded.Delete, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.delete))
        }
    }
    if (renaming) NameDialog(stringResource(R.string.rename), name, { renaming = false }) { Engine.renamePlaylist(id, it); renaming = false }
}

// MARK: Photos (publications TikTok, Instagram…)

private fun LazyGridScope.photos(all: List<Entry>) {
    val folders = all.filter { it.isFolder }
    if (folders.isEmpty()) {
        full { EmptyState(stringResourceSafe(R.string.no_photos)) }
        return
    }
    items(folders, key = { "ph-" + it.path }) { entry ->
        val first = File(entry.path).listFiles()?.filter { it.extension.lowercase() in setOf("jpg", "jpeg", "png", "webp") }?.minByOrNull { it.name }
        val selection = LibraryModel.selection
        Column(Modifier.clip(RoundedCornerShape(14.dp)).clickable {
            if (selection.active) selection.toggle(entry.path) else LibraryModel.gallery = entry.path
        }) {
            Box {
                if (first != null) {
                    AsyncImage(first, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(12.dp)))
                } else {
                    Thumb(entry.thumbnail, null, modifier = Modifier.fillMaxWidth().aspectRatio(1f), folder = true)
                }
                if (selection.active) {
                    SelectionCheck(selection.isSelected(entry.path), Modifier.align(Alignment.TopStart).padding(6.dp))
                }
            }
            Spacer(Modifier.height(6.dp))
            Text(entry.title, color = Color.White, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun Gallery(path: String, onClose: () -> Unit) {
    val images = remember(path) {
        File(path).listFiles()?.filter { it.extension.lowercase() in setOf("jpg", "jpeg", "png", "webp", "gif") }?.sortedBy { it.name } ?: emptyList()
    }
    var zoom by remember { mutableStateOf<File?>(null) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.statusBarsPadding().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = accent) }
            Text(File(path).name, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        LazyVerticalGrid(GridCells.Adaptive(120.dp), contentPadding = PaddingValues(8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            itemsIndexed(images, key = { _, f -> f.absolutePath }) { _, file ->
                AsyncImage(file, null, contentScale = ContentScale.Crop,
                    modifier = Modifier.aspectRatio(1f).clip(RoundedCornerShape(8.dp)).clickable { zoom = file })
            }
        }
    }
    zoom?.let { file ->
        Box(Modifier.fillMaxSize().background(Color.Black).clickable { zoom = null }, contentAlignment = Alignment.Center) {
            AsyncImage(file, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        }
    }
}

/** stringResource utilisable depuis les constructeurs de grilles (appelé dans un item composable). */
@Composable
fun stringResourceSafe(id: Int, vararg args: Any): String = stringResource(id, *args)
