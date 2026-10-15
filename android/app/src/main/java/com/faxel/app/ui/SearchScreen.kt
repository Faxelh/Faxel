package com.faxel.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.app.R
import com.faxel.app.data.Prefs
import com.faxel.app.data.SearchResult
import com.faxel.app.engine.Engine

object SearchModel {
    var query by mutableStateOf("")
    var results by mutableStateOf<List<SearchResult>>(emptyList())
    var loading by mutableStateOf(false)
    var searched by mutableStateOf(false)
    var sent by mutableStateOf<Set<String>>(emptySet())

    fun run() {
        val q = query.trim()
        if (q.isEmpty()) return
        loading = true
        Engine.search(q) { found ->
            if (query.trim() != q) return@search
            results = found
            loading = false
            searched = true
        }
    }
}

/** Recherche YouTube : appuyer sur un résultat l'analyse, la flèche le télécharge tout de suite. */
@Composable
fun SearchScreen(onClose: () -> Unit) {
    val model = SearchModel
    val focus = LocalFocusManager.current
    val requester = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (model.results.isEmpty()) runCatching { requester.requestFocus() } }

    Column(Modifier.fillMaxSize().background(Color(0xFF0B0B0F)).blockTouches()) {
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = accent) }
            OutlinedTextField(
                value = model.query,
                onValueChange = { model.query = it },
                singleLine = true,
                placeholder = { Text(stringResource(R.string.search_hint)) },
                leadingIcon = { Icon(Icons.Rounded.Search, null) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { focus.clearFocus(); model.run() }),
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Surface1, focusedContainerColor = Surface1),
                modifier = Modifier.weight(1f).focusRequester(requester),
            )
        }
        when {
            model.loading -> Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            model.searched && model.results.isEmpty() -> EmptyState(stringResource(R.string.no_results), icon = Icons.Rounded.Search)
            !model.searched -> EmptyState(stringResource(R.string.search_title), stringResource(R.string.search_subtitle), Icons.Rounded.Search)
        }
        LazyVerticalGrid(
            GridCells.Adaptive(if (Layout.wide) 260.dp else 600.dp),
            contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(model.results, key = { it.url }) { result ->
                ResultRow(result, sent = result.url in model.sent, onOpen = {
                    Engine.pendingAutoDownload = false
                    Engine.pendingLink = result.url
                }, onDownload = {
                    model.sent = model.sent + result.url
                    Engine.download(listOf(Triple(result.url, result.title, "youtube")), Prefs.defaultMedia.value,
                        if (Prefs.defaultMedia.value == "audio") BEST else Prefs.defaultQuality.value)
                })
            }
        }
    }
}

@Composable
private fun ResultRow(result: SearchResult, sent: Boolean, onOpen: () -> Unit, onDownload: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable(onClick = onOpen), verticalAlignment = Alignment.CenterVertically) {
        Box {
            Thumb(result.thumbnail, null, modifier = Modifier.width(150.dp).aspectRatio(16f / 9f))
            result.duration?.takeIf { it > 0 }?.let {
                Text(formatTime(it), color = Color.White, fontSize = 11.sp,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).clip(RoundedCornerShape(5.dp))
                        .background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = 5.dp, vertical = 1.dp))
            }
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(result.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(result.uploader, color = Muted, fontSize = 12.sp, maxLines = 1)
        }
        IconButton(onClick = onDownload, enabled = !sent) {
            Icon(Icons.Rounded.Download, null, tint = if (sent) Muted else accent, modifier = Modifier.size(26.dp))
        }
    }
}
