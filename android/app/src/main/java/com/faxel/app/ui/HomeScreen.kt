package com.faxel.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.faxel.app.R
import com.faxel.app.data.Prefs
import coil.compose.AsyncImage

@Composable
fun HomeScreen(onNavigate: (Tab) -> Unit, onSearch: () -> Unit, onCompression: () -> Unit) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        SimpleDateFormat("EEEE d MMMM", Locale.getDefault()).format(Date()).uppercase(Locale.getDefault()),
                        color = Muted, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                    )
                    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                    val greetingRes = when {
                        hour < 5 || hour >= 18 -> R.string.home_greeting_evening
                        hour >= 12 -> R.string.home_greeting_afternoon
                        else -> R.string.home_greeting_morning
                    }
                    val greeting = stringResource(greetingRes)
                    Text("$greeting\n${Prefs.profileName.value}", color = androidx.compose.ui.graphics.Color.White,
                        fontSize = 34.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold)
                }
                IconButton(onClick = onSearch, modifier = Modifier.size(58.dp).clip(CircleShape).background(Surface2)) {
                    Icon(Icons.Rounded.Search, stringResource(R.string.search_title), tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(28.dp))
                }
                Spacer(Modifier.size(10.dp))
                Box(Modifier.size(66.dp).clip(CircleShape).background(Surface2).clickable { onNavigate(Tab.Settings) }, contentAlignment = Alignment.Center) {
                    if (Prefs.profilePhoto.value.isNotBlank()) AsyncImage(Prefs.profilePhoto.value, null, contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().clip(CircleShape))
                    else Icon(Icons.Rounded.Person, null, tint = Muted, modifier = Modifier.size(38.dp))
                }
            }
        }
        item { HomeAction(Icons.Rounded.Download, stringResource(R.string.tab_download), stringResource(R.string.home_download_hint)) { onNavigate(Tab.Download) } }
        item { HomeAction(Icons.Rounded.VideoLibrary, stringResource(R.string.tab_library), stringResource(R.string.home_library_hint)) { onNavigate(Tab.Library) } }
        item { HomeAction(Icons.Rounded.Language, stringResource(R.string.tab_browser), stringResource(R.string.home_browser_hint)) { onNavigate(Tab.Browser) } }
        item { HomeAction(Icons.Rounded.Settings, stringResource(R.string.tab_settings), stringResource(R.string.home_settings_hint)) { onNavigate(Tab.Settings) } }
        item { HomeAction(Icons.Rounded.VideoLibrary, stringResource(R.string.home_compress), stringResource(R.string.home_compress_hint), onCompression) }
    }
}

@Composable
private fun HomeAction(icon: ImageVector, title: String, detail: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = accent, modifier = Modifier.size(28.dp))
        Spacer(Modifier.size(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = androidx.compose.ui.graphics.Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(detail, color = Muted, fontSize = 13.sp)
        }
    }
}
